# About

[![Build status](https://github.com/rgl/terraform-libvirt-ansible-windows-domain-controller-example/workflows/build/badge.svg)](https://github.com/rgl/terraform-libvirt-ansible-windows-domain-controller-example/actions?query=workflow%3Abuild)

Terraform, Ansible, and Windows Domain Controller integration playground.

## Usage (Ubuntu 24.04 host)

Create and install the [base Windows 2022 vagrant box](https://github.com/rgl/windows-vagrant).

Install the dependencies:

* [Docker](https://docs.docker.com/engine/install/).
* [Visual Studio Code](https://code.visualstudio.com).
* [Dev Container plugin](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers).

Open this directory with the Dev Container plugin.

Open `bash` inside the Visual Studio Code Terminal.

Create the infrastructure:

```bash
terraform init
terraform plan -out=tfplan
time terraform apply tfplan
```

**NB** if you have errors alike `Could not open '/var/lib/libvirt/images/terraform-libvirt-ansible-windows-domain-controller-example_dm_root.img': Permission denied'` you need to reconfigure libvirt by setting `security_driver = "none"` in `/etc/libvirt/qemu.conf` and restart libvirt with `sudo systemctl restart libvirtd`.

Show information about the libvirt/qemu guest:

```bash
virsh dumpxml terraform-libvirt-ansible-windows-domain-controller-example-dc
virsh qemu-agent-command terraform-libvirt-ansible-windows-domain-controller-example-dc '{"execute":"guest-info"}' --pretty
virsh qemu-agent-command terraform-libvirt-ansible-windows-domain-controller-example-dc '{"execute":"guest-network-get-interfaces"}' --pretty
# NB the first command after a (re)boot will take some minutes until
#    qemu-agent and winrm are available. the commands that follow it
#    should execute quickly.
# NB these command are executed as the local system user.
./qemu-agent-guest-exec terraform-libvirt-ansible-windows-domain-controller-example-dc winrm enumerate winrm/config/listener
./qemu-agent-guest-exec terraform-libvirt-ansible-windows-domain-controller-example-dc winrm get winrm/config
```

Get the guests ssh host public keys, convert them to the knowns hosts format,
and show their fingerprints:

```bash
for n in dc dm; do
  ./qemu-agent-guest-exec-get-sshd-public-keys.sh \
    "terraform-libvirt-ansible-windows-domain-controller-example-$n" \
    | tail -1 \
    | jq -r .sshd_public_keys \
    | sed "s/^/$(terraform output --raw "${n}_ip_address") /" \
    > "$n-ssh-known-hosts.txt"
  ssh-keygen -l -f "$n-ssh-known-hosts.txt"
done
```

Using your ssh client, open a shell inside the `dc` VM and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=dc-ssh-known-hosts.txt \
  "vagrant@$(terraform output --raw dc_ip_address)"
```
```bat
echo %computername%
whoami /all
exit
```

Configure the infrastructure:

```bash
#ansible-doc -l # list all the available modules
ansible-inventory --list --yaml
ansible-lint --offline --parseable playbook.yml
ansible-playbook playbook.yml --syntax-check
ansible-playbook playbook.yml --list-hosts

# execute ad-hoc commands.
ansible -vvv -m gather_facts dm
ansible -vvv -m win_ping dm
ansible -vvv -m win_command -a 'whoami /all' dm
ansible -vvv -m win_shell -a '$FormatEnumerationLimit = -1; dir env: | Sort-Object Name | Format-Table -AutoSize | Out-String -Stream -Width ([int]::MaxValue) | ForEach-Object {$_.TrimEnd()}' dm

# execute the playbook.
# see https://docs.ansible.com/ansible-core/2.20/os_guide/intro_windows.html
# see https://docs.ansible.com/ansible-core/2.20/os_guide/windows_usage.html
# see https://docs.ansible.com/ansible-core/2.20/os_guide/windows_winrm.html#winrm-limitations
time ansible-playbook playbook.yml #-vvv
time ansible-playbook playbook.yml --limit dms #-vvv
```

Using your ssh client, open a shell inside the `dc` VM as the `vagrant` local user (since we are logging into the domain controller, this is also a domain user), and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=dc-ssh-known-hosts.txt \
  "vagrant@$(terraform output --raw dc_ip_address)"
```
```bat
echo %computername%
echo %user%
echo %username%
echo %userdomain%
echo %userprofile%
whoami /all
klist
exit
```

Using your ssh client, open a shell inside the `dm` VM as the `vagrant` local user, and execute some commands:

```bash
ssh \
  -o UserKnownHostsFile=dm-ssh-known-hosts.txt \
  "vagrant@$(terraform output --raw dm_ip_address)"
```
```bat
echo %computername%
echo %user%
echo %username%
echo %userdomain%
echo %userprofile%
whoami /all
exit
```

Using your ssh client, open a shell inside the `dm` VM as the `alice` domain user, and execute some commands:

```bash
SSHPASS=HeyH0Password sshpass -e \
  ssh \
  -o UserKnownHostsFile=dm-ssh-known-hosts.txt \
  "example\\alice@$(terraform output --raw dm_ip_address)"
```
```bat
echo %computername%
echo %user%
echo %username%
echo %userdomain%
echo %userprofile%
whoami /all
klist
:: use the share as the current user.
echo %time% %user% >\\DC\Share\test.txt
type \\DC\Share\test.txt
klist
:: use the share as the other user.
:: NB alice can write to the share.
:: NB bob can only read from the share.
if "%username%"=="alice" (set otherusername=bob) else (set otherusername=alice)
set otheruser=%userdomain%\%otherusername%
net use x: \\DC\Share /user:%otheruser% HeyH0Password
if "%otherusername%"=="bob" (echo NB writes are expected to fail)
echo %time% %otheruser% >\\DC\Share\test.txt
type \\DC\Share\test.txt
net use x: /user:%otheruser% /delete
klist
:: login as the current user, then, try to write gain.
:: NB a re-login is required to flush the previous smb session/credential.
net use x: \\DC\Share /user:%user%
echo %time% %user% >\\DC\Share\test.txt
type \\DC\Share\test.txt
net use x: /user:%user% /delete
klist
exit
```

Destroy the infrastructure:

```bash
time terraform destroy -auto-approve
```

Lint the source code:

```bash
./ansible-lint.sh --offline --parseable playbook.yml
./mega-linter.sh
```

List this repository dependencies (and which have newer versions):

```bash
GITHUB_COM_TOKEN='YOUR_GITHUB_PERSONAL_TOKEN' ./renovate.sh
```

## Windows Management

Ansible can use one of the native Windows management protocols: [psrp](https://docs.ansible.com/ansible-core/2.20/collections/ansible/builtin/psrp_connection.html) (recommended) or [winrm](https://docs.ansible.com/ansible-core/2.20/collections/ansible/builtin/winrm_connection.html).

Its also advisable to use the `credssp` transport, as its the most flexible transport:

| transport   | local accounts | active directory accounts | credentials delegation | encryption |
|-------------|----------------|---------------------------|------------------------|------------|
| basic       | yes            | no                        | no                     | no         |
| certificate | yes            | no                        | no                     | no         |
| kerberos    | no             | yes                       | yes                    | yes        |
| ntlm        | yes            | yes                       | no                     | yes        |
| credssp     | yes            | yes                       | yes                    | yes        |

For more information see the [Ansible CredSSP documentation](https://docs.ansible.com/ansible-core/2.20/os_guide/windows_winrm.html#credssp).
