# Octant Backup Scripts/Examples

## Rsync

Mirror source and destination and drop permissions, using gzip compressing during transfer:
`rsync -avz --no-perms --no-owner --no-group --ignore-existing --remove-source-files /path/to/new/files/ /path/to/existing/directory/`

Sync only new files from source to destination
`rsync -av --ignore-existing /path/to/new/files/ /path/to/existing/directory/`

## Creating/updating TAR archives

Example: 

```bash
#!/bin/bash

# Specify the name of the .tar file
tar_file="archive_name.tar"

# Check if at least one directory is provided
if [ $# -eq 0 ]; then
    echo "Please provide at least one directory to archive."
    exit 1
fi

# Check if the .tar file exists
if [ -f "$tar_file" ]; then
    echo "Performing incremental backup..."
    tar -uvf "$tar_file" "$@"
else
    echo "Creating initial full backup..."
    tar -cvf "$tar_file" "$@"
fi
```

## Creating incremental TAR archives

Example: 

```bash
#!/bin/bash

# Specify the name of the .tar file
tar_file="archive_name.tar"

# Specify the name of the snapshot file
snapshot_file="snapshot_file.snar"

# Check if at least one directory is provided
if [ $# -eq 0 ]; then
    echo "Please provide at least one directory to archive."
    exit 1
fi

# Check if the .tar file exists
if [ -f "$tar_file" ]; then
    echo "Performing incremental backup..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    tar -cvf "$timestamp_$tar_file" --listed-incremental="$snapshot_file" "$@"
else
    echo "Creating initial full backup..."
    timestamp=$(date +%Y%m%d_%H%M%S)
    tar -cvf "$timestamp_$tar_file" --listed-incremental="$snapshot_file" "$@"
fi
```