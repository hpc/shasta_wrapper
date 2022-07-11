# Shasta Wrapper

Simplifies the administration of cray shasta systems.

## Building
### rpm
1. clone a copy of this repository
```
cd <name of repository directory>
make rpm
```

## Installation
### rpm Install
1. Install the rpm
rpm -ivh <>
### Source Install
1. Retrieve the source code
2. Compile
```
make
```
3. Install (needs root priviledges)
```
sudo make install
```
## Setup
1. shasta_wrapper expects a cfs generated ansible file in /etc/ansible/hosts. The easiest way to set this up is add the following ansible task to your ansible setup on the ncn nodes:
```
- name: drop ansible hosts
  copy:
    src: '{{ inventory_file }}'
    dest: '/etc/ansible/hosts'
    owner: 'root'
    group: 'root'
    mode: 0600
```
2. Get the ims public key id from ims (should have been created as part of the system installation, if not see the install guide for the IMS_PUBLIC_KEY_ID):
```
cray ims public-keys list
[
  {
    "created": "1972-01-01T00:00:00.00000+00:00",
    "id": "ad7a58ff-4f5e-063c-f528-8b024d3ec6ff",
    "name": "my public key",
    "public_key": "ssh-rsa XXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\n"
  }
]
```
3. In /etc/cluster_defaults.conf, set the IMS_PUBLIC_KEY_ID to the id from above, and ensure it's uncommented. 
### Setting Defaults
One of the main features of the shasta wrapper is the support of setting defaults for ansible groups. Defaults are set in /etc/cluster_defaults.conf
```
## Compute
BOS_DEFAULT[Compute]="cos-sessiontemplate-2.0.46" # What bos template to use for boot/configure/etc actions for this group
RECIPE_DEFAULT[Compute]="8d3d3c30-e93a-4aa2-be8c-08092ae1006a" # What recipe id to use to build images
IMAGE_DEFAULT_NAME[Compute]="lanl_compute_sles15sp1" # What name to give images built for this group
IMAGE_GROUPS[Compute]="Compute" # Optional override for what group to use when building images
```
NOTE: In this file each of those dictionary keys (in the example above "Compute") must match an ansible group in /etc/ansible/hosts.

### Setting an cfs update targets for git
Inside of /etc/cfs_defaults.conf we can set default targets to update specific git commitids inside of a cfs config. 
```
CFS_BRANCH[cos]=integration # set the branch or tag to update cfs's commits ids to
CFS_URL[cos]="https://api-gw-service-nmn.local/vcs/cray/cos-config-management.git" # The url that needs to match the git url in cfs
```
NOTE: The dictionary key (cos) needs to be unique for each new URL/BRANCH pair.



