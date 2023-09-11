#!/bin/bash

VM_NAME=$1
CONTAINER_DISK_NAME=$2
DISK_FILE=$3
OUTPUT_PATH=./tmp
TEMP_DISK_PATH=$OUTPUT_PATH/$3
REGISTRY_URL=${REGISTRY_HOST}/${REGISTRY_USERNAME}/$CONTAINER_DISK_NAME

function apply_vmexport() {
  echo "Applying VirutalMachineExport object to expose Virutal Machine data..."

	cat << END | kubectl apply -f -
apiVersion: export.kubevirt.io/v1alpha1
kind: VirtualMachineExport
metadata:
  name: $$VM_NAME
spec:
  source:
    apiGroup: "kubevirt.io"
    kind: VirtualMachine
    name: $$VM_NAME
END
}

function download_disk_img() {
  echo "Downloading disk image $DISK_FILE from $$VM_NAME Virutal Machine..."

  usr/bin/virtctl vmexport download $$VM_NAME --vm=$$VM_NAME --output=$TEMP_DISK_PATH

  if [ -e "$TEMP_DISK_PATH" ] && [ -s "$TEMP_DISK_PATH" ]; then
      echo "Donwload completed successfully."
  else
      echo "Download failed."
      exit 1
  fi
}

function convert_disk_img() {
  echo "Converting raw disk image to qcow2 format..."

  gunzip $TEMP_DISK_PATH
  qemu-img convert -f raw -O qcow2 $TEMP_DISK_PATH $OUTPUT_PATH/disk.qcow2
  rm $TEMP_DISK_PATH
}

function build_disk_img() {
  echo "Building exported disk image in a new container image..."

  cat << END > $OUTPUT_PATH/Dockerfile
FROM scratch
ADD --chown=107:107 ./disk.qcow2 /disk/
END
  buildah build -t $CONTAINER_DISK_NAME $OUTPUT_PATH
}

function push_disk_img() {
  echo "Pushing the new container image to container registry..."

  buildah login --username ${REGISTRY_USERNAME} --password ${REGISTRY_PASSWORD} ${REGISTRY_HOST}
  buildah tag $CONTAINER_DISK_NAME $REGISTRY_URL
  buildah push $REGISTRY_URL
}

apply_vmexport
download_disk_img
convert_disk_img
build_disk_img
push_disk_img

echo "Succesfully extracted disk image and uploaded it in a new container image to container registry."
