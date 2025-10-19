#!/bin/bash

## Load the config file
source "/etc/libvirt/hooks/kvm.conf"

echo "Allocating hugepages for VM: $VM_NAME"

## USE THE PRE-CALCULATED VALUE DIRECTLY - NO RECALCULATION NEEDED
HUGEPAGES=$MEMORY

echo "Allocating $HUGEPAGES hugepages..."
echo $HUGEPAGES > /proc/sys/vm/nr_hugepages
ALLOC_PAGES=$(cat /proc/sys/vm/nr_hugepages)

TRIES=0
while (( $ALLOC_PAGES != $HUGEPAGES && $TRIES < 1000 ))
do
    echo 1 > /proc/sys/vm/compact_memory            ## defrag ram
    echo $HUGEPAGES > /proc/sys/vm/nr_hugepages
    ALLOC_PAGES=$(cat /proc/sys/vm/nr_hugepages)
    echo "Successfully allocated $ALLOC_PAGES / $HUGEPAGES"
    let TRIES+=1
done

if [ "$ALLOC_PAGES" -ne "$HUGEPAGES" ]
then
    echo "Not able to allocate all hugepages. Reverting..."
    echo 0 > /proc/sys/vm/nr_hugepages
    exit 1
fi

echo "HugePages allocation completed successfully!"
grep -i huge /proc/meminfo
