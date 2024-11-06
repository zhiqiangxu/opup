# opup, one-stop installation tool for OP Stack


# usage

To start all processes, just run `just up`.
 
If anything goes wrong, it'll stop immediately, indicating the exact line that's triggering it.

If everything goes well, it'll spin up these processes:

![all-processes](assets/all-processes.png)

(Each process is managed in a separate [screen](https://linuxize.com/post/how-to-use-linux-screen/) session.)

To shut down all processes, just run `just down`.