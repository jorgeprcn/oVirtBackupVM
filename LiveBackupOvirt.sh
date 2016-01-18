#!/bin/bash

# NAME: Live Backup of VMs with Active Block Commit
# AUTHOR: Jorge Junior
# DESCRIPTION: Live backup of VMs on KVM, being managed by oVirt, using the active block commit feature. It copies the raw (tar'ed) file to the designated backup server.
# USAGE: Cron, weekly. This script is supposed to be ran at the oVirt engine node.
# PROCESSNAME: virsh
# CONFIG: within the script, variables

# IMPORTANT NOTES:
# Remember to create a user on each KVM host first, using sasl2passwd first
# saslpasswd2 -a libvirt backup
#
# Copy your SSH key (oVirt Engine) to the other KVM hosts and Backup server
# ssh-keygen
# ssh-copy-id
#
# Make sure to have libvirt-client installed
# yum -y install libvirt-client

# Variables:
USER="backup"						# User created with saslpasswd2 on each KVM host
PASS="Pass2015"						# Password for the user created with saslpasswd2
KVM01="kvm01"						# KVM host, add more if necessary
KVM02="kvm02"						# KVM host, add more if necessary
VMKVM01="/var/log/vmList01.log"				# VM List KVM Host 01
VMKVM02="/var/log/vmList02.log"				# VM List KVM Host 02
VMDISK="/var/log/vmDisk.log"				# VM Disk
SNAPLOC="/rhev/data-center/00000002-0002-0002-0002-00000000020c/042b84a1-c660-441d-aa3c-9f999bb9590e/images/"	# Place Snapshot
LOG="/var/log/backupKVM.log"				# Log
DESTSERVER="backup.server.com:/path/to/directory"	# SSH Server and path to place the resulting backup
FILEPREFIX="backupKVM-"					# Name prefix for the backup
SNAPPREFIX="snapKVM-"					# Name prefix for the snapshot

# Create auth.conf file for virsh to use		
echo -e "[credentials-"$KVM01"]" > /etc/libvirt/auth.conf
echo -e "authname="$USER >> /etc/libvirt/auth.conf
echo -e "password="$PASS"\n" >> /etc/libvirt/auth.conf
echo -e "[credentials-"$KVM02"]" >> /etc/libvirt/auth.conf
echo -e "authname="$USER >> /etc/libvirt/auth.conf
echo -e "password="$PASS"\n" >> /etc/libvirt/auth.conf

echo -e "[auth-libvirt-"$KVM01"]" >> /etc/libvirt/auth.conf
echo -e "credentials="$KVM01"\n" >> /etc/libvirt/auth.conf
echo -e "[auth-libvirt-"$KVM02"]" >> /etc/libvirt/auth.conf
echo -e "credentials="$KVM02"\n" >> /etc/libvirt/auth.conf

# List information for Guest VMs on all KVM Hosts
virsh -c "qemu+ssh://root@"$KVM01"/system" list --name | grep -v HostedEngine > $VMKVM01
virsh -c "qemu+ssh://root@"$KVM02"/system" list --name | grep -v HostedEngine > $VMKVM02

# Does all the backup related tasks on VMs hosted on Host 1
for VM in $(cat $VMKVM01); do
	virsh -c "qemu+ssh://root@"$KVM01"/system" domblklist $VM | grep vda | sed -r 's/.* //' > $VMDISK
	cat $VMDISK
	ssh "root@"$KVM01 touch $SNAPLOC$SNAPPREFIX$VM".qcow2"
	ssh "root@"$KVM01 chmod 777 $SNAPLOC$SNAPPREFIX$VM".qcow2"
	ssh "root@"$KVM01 touch $SNAPLOC$FILEPREFIX$VM".tar"
	ssh "root@"$KVM01 chmod 777 $SNAPLOC$FILEPREFIX$VM".tar"
	virsh -c "qemu+ssh://root@"$KVM01"/system" snapshot-create-as --domain $VM $SNAPPREFIX$VM".qcow2" --diskspec "vda,file="$SNAPLOC$SNAPPREFIX$VM".qcow2" --disk-only --atomic
	echo -e "Snapshot for" $VM "created with success" >> $LOG
	ssh "root@"$KVM01 tar cf $SNAPLOC$FILEPREFIX$VM".tar" $(cat $VMDISK)
	scp "root@"$KVM01":"$SNAPLOC$FILEPREFIX$VM".tar" "root@"$DESTSERVER
	echo -e "The disk" $SNAPLOC$FILEPREFIX$VM".tar" "of" $VM "copied to" $DESTSERVER "with success" >> $LOG
	virsh -c "qemu+ssh://root@"$KVM01"/system" blockcommit $VM vda --active --verbose --pivot
	echo -e $VM "is using its original disk again" >> $LOG
	virsh -c "qemu+ssh://root@"$KVM01"/system" snapshot-delete $VM $SNAPPREFIX$VM".qcow2" --metadata
	echo -e "Snapshot" $SNAPPREFIX$VM "for" $VM "is deleted" >> $LOG
	ssh "root@"$KVM01 rm -rf $SNAPLOC$SNAPPREFIX$VM".qcow2"
	ssh "root@"$KVM01 rm -rf $SNAPLOC$FILEPREFIX$VM".tar"
done

# Does all the backup related tasks on VMs hosted on Host 2
for VM in $(cat $VMKVM02); do
	virsh -c "qemu+ssh://root@"$KVM02"/system" domblklist $VM | grep vda | sed -r 's/.* //' > $VMDISK
	cat $VMDISK
	ssh "root@"$KVM02 touch $SNAPLOC$SNAPPREFIX$VM".qcow2"
	ssh "root@"$KVM02 chmod 777 $SNAPLOC$SNAPPREFIX$VM".qcow2"
	ssh "root@"$KVM02 touch $SNAPLOC$FILEPREFIX$VM".tar"
	ssh "root@"$KVM02 chmod 777 $SNAPLOC$FILEPREFIX$VM".tar"
	virsh -c "qemu+ssh://root@"$KVM02"/system" snapshot-create-as --domain $VM $SNAPPREFIX$VM".qcow2" --diskspec "vda,file="$SNAPLOC$SNAPPREFIX$VM".qcow2" --disk-only --atomic
	echo -e "Snapshot for" $VM "created with success" >> $LOG
	ssh "root@"$KVM02 tar cf $SNAPLOC$FILEPREFIX$VM".tar" $(cat $VMDISK)
	scp "root@"$KVM02":"$SNAPLOC$FILEPREFIX$VM".tar" "root@"$DESTSERVER
	echo -e "The disk" $SNAPLOC$FILEPREFIX$VM".tar" "of" $VM "copied to" $DESTSERVER "with success" >> $LOG
	virsh -c "qemu+ssh://root@"$KVM02"/system" blockcommit $VM vda --active --verbose --pivot
	echo -e $VM "is using its original disk again" >> $LOG
	virsh -c "qemu+ssh://root@"$KVM02"/system" snapshot-delete $VM $SNAPPREFIX$VM".qcow2" --metadata
	echo -e "Snapshot" $SNAPPREFIX$VM "for" $VM "is deleted" >> $LOG
	ssh "root@"$KVM02 rm -rf $SNAPLOC$SNAPPREFIX$VM".qcow2"
	ssh "root@"$KVM02 rm -rf $SNAPLOC$FILEPREFIX$VM".tar"
done
