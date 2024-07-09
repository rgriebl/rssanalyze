### rssanalyze.pl

A very good way to analyze a Linux process' memory consumption is the analyzer script written by Qt's Corelib maintainer Thiago Macieira:

https://gitlab.com/thiagomacieira/rssanalyse

It's a simple Perl script that you can call with at least one PID as an argument. Typically you would run `rssanalyse.pl $(pidof <your binary name>)`.

This version adds documentation, changes the spelling to American English and adds the `--proc=` command line argument.

Example output:

```
 Total mapped memory:     830728 kB
    of which swapped out: 0 kB
   of which likely stack: 57512 kB mapped, 288 kB resident (164 kB main, 124 kB aux threads)
   of which are resident: 149528 kB, 70560 kB proportionally shared
         total anonymous: 43460 kB (29.1%)
                  Shared: 103132 kB total (69.0% of RSS)
               Breakdown: 103132 kB clean (100.0%), 0 kB dirty (0.0%)
                          57904 kB code (56.1%), 45180 kB RO data (43.8%), 48 kB RW data (0.0%)
                          0 kB heap (0.0%), 0 kB stack (0.0%), 0 kB other (0.0%)
                 Private: 46396 kB total (31.0% of RSS)
               Breakdown: 2776 kB clean (6.0%), 43620 kB dirty (94.0%)
                          116 kB code (0.3%), 6120 kB RO data (13.2%), 6596 kB RW data (14.2%)
                          33276 kB heap (71.7%), 288 kB stack (0.6%), 0 kB other (0.0%)
```

You can also add `-v` and `-vv` to get a very verbose report where you can exactly see which shared library attributed how much to the memory totals.

If you cannot execute a Perl script on an embedded target, you can copy the needed `/proc/<pid>/smaps` files to your development machine (e.g. to `/tmp/targetproc/<pid>/smaps`) and then start rssanalyze.pl with `--proc=/tmp/targetproc` to redirect any `/proc` access.

The original script does however lack an explanation for all the values it reports:

- **Total mapped memory** or **VSZ** or *VIRT* in htop

  All the virtual memory allocated by the process, but not necessarily used. Can be very high in multi-threaded applications, because glibc reserves a huge stack (8MB) plus heap (64MB) for every thread, but only a few kB of those are hardly ever used.
  It includes all memory that the process can access, including memory that is swapped out, memory that is allocated, but not used, and memory that is from shared libraries.
     
- **Padding**

  Filler regions that are never mapped, but are necessary to align the memory pages.
  
- **Swap**

  Not applicable on embedded systems.
     
- **Resident** or **RSS** (Resident Set Size) or *RES* in htop

  Actual physical memory used by the process. This is the *hot* part of the **total mapped memory**, i.e. the memory the process is actively accessing right now.
  It does include memory from shared libraries as long as the pages from those libraries are actually in memory. It does include all stack and heap memory.

- **Anonymous**

  A memory region that is not backed by a file (hence *anonymous*). These mappings are mainly used for heaps and stacks, but process can create their own (e.g. the JS heap)
  
- **Shared** or *SHR* in htop
  
  A subset of "resident", but this memory is shared with other processes. This can be explicitly shared memory mapping, but most likely the footprint of shared libraries.

- **Proportionally Shared** or **PSS** (Proportional Set Size)
  
  **Shared** only tells you the absolute amount of memory that is shared, but it doesn't tell you if it is shared efficiently (e.g. with 20 other processes) or inefficiently (e.g. just 2 other). Also, if you add up all of the RSS values you can easily end up with more memory than your system has to begin with.

  This is where PSS (proportional set size) comes in handy: this tracks the shared memory as a proportion used by the current process. So if **n** processes use the same shared library, the library's total shared memory segments will be attributed to the PSS value of each of the processes with a factor of **1/n**.

- **Private**
  
  A subset of **resident**, but this memory is currently not shared with other processes. Please note that the **clean** part of the **private** memory could in theory be shared: the most likely reason it isn't, comes from shared libraries that are only used by this process right now.
  
- **Clean**

  All clean pages can be discarded on memory pressure and reloaded from disk.

- **Dirty**

  Dirty pages are memory pages that cannot be discarded/reloaded, as they hold live data that the process is working on. Most of these are private (heaps and stacks), but a shared memory mapping between processes can both be dirty and shared.
  
- **Code**

  The actual binary executable code - this should always be clean.
  
- **RO data**

  Read-only data segment: parts can be clean (ELF .rodata), but other parts can be dirty, because they are dynamically allocated.
    
- **RW data**

  This memory is always dirty, as this is the working memory: mostly the heaps and stacks of all the threads.
  
**Please note:** Threads all share the same address space, so all the threads within one process have identical VSZ, RSS and PSS values.
