# Week 3 script phases -> Ansible modules

| Week 3 phase | Ansible module |
|---|---|
| 1 packages | apt (cache_valid_time) |
| 2 service accounts | group, user |
| 3 directories + ACLs | file, ansible.posix.acl |
| 4 systemd units | template + systemd handler |
| 5 firewall | community.general.ufw |
| 6 journal persistence | template on journald.conf + handler |
| 7 logrotate | template |
| 8 verify | uri / command with changed_when: false |
