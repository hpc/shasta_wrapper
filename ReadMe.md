# Shasta Wrapper

Scripting to simplify the administration of HPE Cray EX Systems

## License
This program is open source under the BSD-3 License.
Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following conditions are met:
 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
 3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



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
3. In /etc/shasta_wrapper/cluster_defaults.conf, set the IMS_PUBLIC_KEY_ID to the id from above, and ensure it's uncommented. 
### Setting Defaults
One of the main features of the shasta wrapper is the support of setting defaults for ansible groups. Defaults are set in /etc/shasta_wrapper/cluster_defaults.conf
```
## Compute
BOS_DEFAULT[Compute]="cos-sessiontemplate-2.0.46" # What bos template to use for boot/configure/etc actions for this group
RECIPE_DEFAULT[Compute]="8d3d3c30-e93a-4aa2-be8c-08092ae1006a" # What recipe id to use to build images
IMAGE_DEFAULT_NAME[Compute]="lanl_compute_sles15sp1" # What name to give images built for this group
IMAGE_GROUPS[Compute]="Compute" # Optional override for what group to use when building images
```
NOTE: In this file each of those dictionary keys (in the example above "Compute") must match an ansible group in /etc/ansible/hosts.

### Setting an cfs update targets for git
Inside of /etc/shasta_wrapper/cfs_defaults.conf we can set default targets to update specific git commitids inside of a cfs config. 
```
CFS_BRANCH[cos]=integration # set the branch or tag to update cfs's commits ids to
CFS_URL[cos]="https://api-gw-service-nmn.local/vcs/cray/cos-config-management.git" # The url that needs to match the git url in cfs
```
NOTE: The dictionary key (cos) needs to be unique for each new URL/BRANCH pair.



