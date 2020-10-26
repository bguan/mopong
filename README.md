# MoPong

Mobile Version of Classic Pong Game for Educational Purpose.

This is the Third in a series of projects for various Pong like games following [PyPong](https://github.com/bguan/pypong) and [Scratch Pong](https://scratch.mit.edu/projects/433809822).

This version is implemented using my favorite cross platform mobile development framework [Flutter](https://flutter.dev/) and the game engine [Flame](https://flame-engine.org/).

The goal is to use as simple as possible techniques, not to be distracted by the bells and whistles of modern game engines.

For a sense of scale:
* 1 player version against CPU ~200 lines of dart, took ~1 day to get working
* 2 player 2 device version over LAN w/ UDP and ZeroConf, ~600 lines of dart, took ~1 day to prototype, 2 days to stabilize, another 2 days to optimize
  * initial version uses gyroscope but switched to finger drag for better precision
  * optimization involve trading responsibility of true ball state calculation so not to favor the hosting device vs guest device. 
  * If ball is coming to you, your device is doing the ball position calculation and score keeping.
  * Both players send to eachother their paddle position using UDP, ball calculator also sends boll and score data.
  * If one device disconnect from network, the other will timeout too and not stuck in permanent waiting state.
  * All coordinates and dimension are device resolution independent.
