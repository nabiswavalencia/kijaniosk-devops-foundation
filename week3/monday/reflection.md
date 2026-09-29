# Monday reflection

## 1. The /proc boundary
`/proc` is a virtual filesystem. Nothing in it is stored on disk: the kernel builds each file at the moment I read it, from its live tables of processes and memory. That is why `ps aux`, `top` and `free` all read from it, and why it is rebuilt from nothing after a reboot. For my investigation this means everything I saw from `/proc` was a snapshot of one moment, not a history. When I read `VmRSS` or `MemAvailable` I was seeing the machine right then. That is why I recorded a healthy baseline before starting (160 Mi used at 13:03), and why I used the log files to find out what happened earlier. A process that had already exited, like the original memory process from the setup script, left nothing in `/proc` at all.

## 2. Kernel space and process isolation
The CPU runs code in privilege levels. The kernel runs at the highest level and user programs at a lower one, and the memory manager gives every process its own virtual address space. A user process cannot address kernel memory or another process's memory. To do anything privileged it must ask the kernel through a system call, and the kernel decides. My Python process allocated about 500 MB, and the worst it could do was use up free memory. The rest of the server kept working. Without this boundary, one bug or one hostile program could overwrite kernel data or another process's memory, and a single memory leak in an ordinary application could crash or take over the whole machine.

## 3. The triage pipeline I built
The most complex command was Osei's file descriptor benchmark:
```
find /proc -maxdepth 3 -name fd -type d | awk -F/ '{print $3}' | xargs -I{} sh -c 'echo "$(ls /proc/{}/fd | wc -l) {}"' | sort -rn | head -5
```
- `find` lists every `/proc/<PID>/fd` directory, one per process.
- `awk -F/ '{print $3}'` splits each path on `/` and keeps the third piece, the PID.
- `xargs` runs a small shell once per PID, which counts the entries in that process's `fd` folder and prints "count PID".
- `sort -rn` sorts by that count, highest first.
- `head -5` keeps the top five.

If I swapped `sort` and `head`, I would get the first five PIDs found, not the five biggest. The same logic applies to `sort | uniq -c`: `uniq` only merges neighbouring duplicate lines, so it needs sorted input. I also learned that without `sudo` the command only counts my own processes, which gave a different top entry (28 descriptors for my `systemd --user`, against 73 for PID 1).

## 4. Containers and the kernel
A container is an ordinary Linux process that the kernel has been told to give a restricted view: its own process ID numbering, network stack, mounts and hostname (namespaces), and limits on CPU and memory (cgroups). There is no separate operating system inside it. It shares the host's kernel, so the host can see the container's processes in its own `ps aux` with different PIDs. What a container provides is isolation of what a process can see and use, not a separate machine. That is weaker than a virtual machine, where a separate kernel sits between the workload and the host.

## 5. Operational consequence
The memory process was a symptom. The application log shows the chain: the database connection pool was at 85 percent at 03:45 and 94 percent at 04:01, and was exhausted at 04:07:55. Requests began queuing and queries timed out after 30 seconds. That is what users would experience as slow responses, and the queued requests explain memory rising (87 percent at 04:09). At 06:22 the database refused connections, and the retry limit was reached. So the cascade is pool filling, pool exhaustion, timeouts and queuing, memory growth, then the database becoming unreachable. My live checks agree: the disk, kernel and network were clean, and the `database` host name does not resolve on this server.
