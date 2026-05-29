#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_FILE="${1:?missing config file}"
RUNTIME_BASE="/run/pbs-file-backup"

mkdir -p "$RUNTIME_BASE"

LOCKFILE="${RUNTIME_BASE}/lock"

exec 9>"$LOCKFILE"

flock -n 9 || {
	log "Another backup process is already running."
	exit 1
}

timestamp() {
	date +"%Y%m%d-%H%M%S"
}

random_id() {
	openssl rand -hex 4	
}

log() {
	echo "[$(date --iso-8601=seconds)] $*"
}

cleanup() {
	local errexit_set=0
	[[ $- == *e* ]] && errexit_set=1
	set +e

	if [[ -n "${WORK_MOUNT:-}" ]]; then
		if mountpoint -q "$WORK_MOUNT"; then
			log "Unmounting $WORK_MOUNT"
			umount "$WORK_MOUNT" || umount -l "$WORK_MOUNT"
		fi
	fi

	if [[ -n "${LVM_SNAP_PATH:-}" ]]; then
		log "Removing LVM snapshot $LVM_SNAP_PATH"
		udevadm settle
		kpartx -dv "${LVM_SNAP_PATH}" 9>&- || true
		lvremove -fy "$LVM_SNAP_PATH" 9>&- || true
	fi

	if [[ -n "${CLONE_DATASET:-}" ]]; then
		log "Destroying ZFS clone $CLONE_DATASET"
		zfs destroy -r "$CLONE_DATASET" 9>&- || true
	fi

	if [[ -n "${SNAPSHOT_NAME:-}" ]]; then
		log "Destroying ZFS snapshot $SNAPSHOT_NAME"
		zfs destroy "$SNAPSHOT_NAME" 9>&- || true	
	fi

	if [[ -n "${WORK_MOUNT:-}" ]]; then
		log "Removing directory $WORK_MOUNT"
		rmdir "$WORK_MOUNT" 2>/dev/null || true
	fi

	(( errexit_set )) && set -e
}

cleanup_and_exit() {
	local exit_code=$?
	trap - ERR EXIT INT TERM
	cleanup
	exit "$exit_code"
}

trap cleanup_and_exit EXIT INT TERM
trap cleanup_and_exit ERR

backup(){
	export PBS_REPOSITORY
	log "Using PBS repository ${PBS_REPOSITORY}"

	log "Starting the backup of $BACKUP_ID"
	log "NAME=${NAME},WORK_MOUNT=${WORK_MOUNT},BACKUP_ID=${BACKUP_ID}"
	proxmox-backup-client backup \
		"${NAME}.pxar:${WORK_MOUNT}" \
		--backup-id "${BACKUP_ID}" \
		--exclude '**/.cache/**' \
		--exclude '**/.local/share/Trash/**'
	sync
	log "Finished the backup of $BACKUP_ID"
}

unset_variables() {
	unset \
		LVM_SNAP_PATH \
		CLONE_DATASET \
		SNAPSHOT_NAME \
		WORK_MOUNT
}

lvm_backup(){
	log "Starting LVM backup: $NAME"
	local VG LV SNAP_NAME LVM_PART MAPPER LVM_PART1 LVM_PART2
	VG="${SOURCE%%/*}"
	LV="${SOURCE##*/}"
	log "VG=$VG, LV=$LV"
	SNAP_NAME="${LV}-snap-${TS}-${RID}"

	LVM_SNAP_PATH="/dev/${VG}/${SNAP_NAME}"
	
	log "Creating LVM Snapshot: $SNAP_NAME"
	lvcreate \
		-s \
		-n "$SNAP_NAME" \
		"${VG}/${LV}" 9>&-

	lvchange -ay -K "$LVM_SNAP_PATH" 9>&-
	LVM_PART="${LVM_SNAP_PATH}"

	if [[ -n "${PARTITION:-}" && "${PARTITION}" != "0" ]]; then
		log "Partition defined, probing for the partition"
		kpartx -av "$LVM_SNAP_PATH" 9>&-
		MAPPER="/dev/mapper/${VG//-/--}-${SNAP_NAME//-/--}"
		LVM_PART1="${MAPPER}${PARTITION}"
		LVM_PART2="${MAPPER}p${PARTITION}"
		for _ in $(seq 1 30); do
			log "Probing for partition $PARTITION"
			if [[ -b "$LVM_PART1" ]]; then
				LVM_PART="$LVM_PART1"
				break
			elif [[ -b "$LVM_PART2" ]]; then
				LVM_PART="$LVM_PART2"
				break
			fi
			sleep 1
		done
		if [[ ! -b "$LVM_PART1" && ! -b "$LVM_PART2" ]]; then
            		log  "ERROR: partition not found: $MAPPER, partition $PARTITION"
			exit 1
		fi
	fi

	log "Mounting LVM: $LVM_PART on $WORK_MOUNT"
	mkdir -p "$WORK_MOUNT"
	mount \
            -t "$FS_TYPE" \
            -o ro,norecovery,nouuid \
            "$LVM_PART" \
            "$WORK_MOUNT"
	backup
}

zfs_backup(){
	log "Starting ZFS backup: $NAME"
	local CLONE_DEV CLONE_PART
	SNAPSHOT_NAME="${SOURCE}@pbs-${TS}-${RID}"
	CLONE_DATASET="${SOURCE}-clone-${TS}-${RID}"

	zfs snapshot "$SNAPSHOT_NAME" 9>&-

	log "Creating ZFS clone... $SNAPSHOT_NAME $CLONE_DATASET."
	CLONE_DEV="/dev/zvol/${CLONE_DATASET}"
	zfs clone "$SNAPSHOT_NAME" "$CLONE_DATASET" 9>&-

	log "Waiting for clone dev $CLONE_DEV"
	for _ in $(seq 1 30); do
            [[ -b "$CLONE_DEV" ]] && break
            sleep 1
        done

	if [[ ! -b "$CLONE_DEV" ]]; then
            log "ERROR: clone device not found: $CLONE_DEV"
            exit 1
        fi

	CLONE_PART="${CLONE_DEV}"
	if [[ -n "${PARTITION:-}" && "${PARTITION}" != "0" ]]; then
		log "backup of the partition $PARTITION"
		CLONE_PART="${CLONE_DEV}-part${PARTITION}"
		for _ in $(seq 1 30); do
			[[ -b "$CLONE_PART" ]] && break
			sleep 1
		done
	fi
	if [[ ! -b "$CLONE_PART" ]]; then
		log "ERROR: partition not found: $CLONE_PART"
		exit 1
	fi
	log "Mounting '$CLONE_PART' on '$WORK_MOUNT' with filesystem '$FS_TYPE' on '$WORK_MOUNT'"
	mkdir -p "$WORK_MOUNT"
	mount \
            -t "$FS_TYPE" \
	    -o ro,norecovery,nouuid \
            "$CLONE_PART" \
            "$WORK_MOUNT"
	backup
}

while IFS= read -r entry; do
	[[ -z "$entry" || "$entry" =~ ^# ]] && continue

	unset_variables

	IFS='|' read -r \
		NAME \
		TYPE \
		SOURCE \
		PARTITION \
		FS_TYPE \
		PBS_REPOSITORY \
		BACKUP_ID <<< "$entry"
	TS="$(timestamp)"
	RID="$(random_id)"	

	WORK_MOUNT="${RUNTIME_BASE}/${NAME}-${TS}-${RID}"
	if [[ "$TYPE" == "zfs" ]]; then
		zfs_backup
	elif [[ "$TYPE" == "lvm" ]]; then
		lvm_backup
	else
		log "Backup type need to be either zfs or lvm. Review your '$CONFIG_FILE'"
		exit 1
	fi

	cleanup
	unset_variables	

done < "$CONFIG_FILE"
