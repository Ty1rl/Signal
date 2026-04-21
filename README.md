# Signal

A puzzle game about routing a signal across a grid from a transmitter to a receiver.

Built in Godot 4.6.

## Overview

Send a signal from transmitter (*green*) tower to receiver (*purple*) tower by activating towers along the way and re-propagating the signal.  Each propagation reduces the signal integrity.

## Waveforms

**Wide** (*15 Integrity*) propagates outward in a radial pattern across plain tiles. Blocked by rocks and walls.

**Pulse** (*10 Integrity*) propagates in four straight directions. Passes through rocks. Blocked by walls.

**Skip** (*25 Integrity*) propagates through any terrain, including walls. Short range.

## How to play

1. Click an activated tower.
2. Choose a waveform.
3. The signal propagates from that tower according to the waveform's rules.
4. Any tower the signal reaches becomes activatable.
5. Reach the target tower with signal integrity remaining.

Each waveform has its own integrity cost per activation. Choose carefully.

## Levels

The **Tutorials** introduce each waveform one at a time, then show how to chain activations across multiple towers.

There are three levels **Arc** , **Zigzag**, and **Gauntlet**.
