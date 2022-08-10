---
layout: post
title: "Debugging Failures in ROS Integration Tests"
data: 2022-08-09 19:15:00 -0800
---

Today I found myself debugging a CI pipeline failure involving a ROS1 integration. And it was not convenient.

Unfortunately, the CI pipeline at work is making use of `catkin test` and when you use `caktin test`, it suppresses all of the output. One approach that's typically advised is to edit your `roslaunch` file to specify a `launch-prefix`, like is shown [here](http://wiki.ros.org/roslaunch/Tutorials/Roslaunch%20Nodes%20in%20Valgrind%20or%20GDB). As you can see, there's actually quite a few permutations as most people do not develop their ROS nodes to daemonize and instead rely on a program like `screen` to keep their process running and accessible.

I find reaching the exact invocation in the launch-prefix to be pretty inconvenient since I'm usually running a `byobu` session on a remote host. If I don't remember to set up the X server ahead of time it needs to use `screen` and that can conflict with `byobu`. What I really want anyway is all of the fluff out of the way so I can see the backtrace. Turns out it is pretty easy! You'll need to run `roscore` in some process as `roslaunch` and/or `catkin` are doing that for you, but after that you can invoke your node just like any other binary. It can most likely be found under `<CATKIN_WS>/devel/lib/<PACKAGE_NAME>/<NODE_NAME>`. The only additional piece of info you need is the node name being passed in the roslaunch file for the test, otherwise `ros::init` will crash. Then you can do:

```sh
$ gdb <relative path to binary>/<binary filename>

<snip all of the gdb print out>

(gdb) r __name:=NODE_NAME
```

I'm partly writing this post because I find the syntax of the argument passing to be hard to remember since it's very non-standard (to avoid conflicting with normal user arguments I suspect). I can't find any documentation of this syntax anywhere either, but it works with ROS1 Noetic and likely many recent versions of ROS1.