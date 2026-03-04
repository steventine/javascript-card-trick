# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development

Open `index.html` in a browser. There is no build step, no package manager, and no tests.

## Project Overview

A static, single-page implementation of the [JavaScript Card Trick](https://youtu.be/rkrjo4IIb1I) from Dr. Tim Muller (Computerphile). A spectator picks 5 cards; the magician arranges 4 of them in a specific order and the computer predicts the hidden 5th.

Hosted at [magic.tinefamily.com](https://magic.tinefamily.com) via GitHub Pages.

## Files

- `index.html` — Enhanced UI version (the primary file). All JS and CSS are inline.
- `index_tim.html` — Tim's original minimal implementation using dropdown selects.

## Core Algorithm (`index.html`)

All logic lives in inline `<script>` tags. Global state: `pile` (array of up to 4 `{rank, suit}` objects), `revealed` (the computed 5th card), `selectedRank`, `selectedSuit`.

**Card encoding:**
- Ranks: 2–10 as integers, J=11, Q=12, K=13, A=14
- Suits: `"c"`, `"h"`, `"s"`, `"d"` — CHaSeD ordering maps to 1, 2, 3, 4 respectively

**Prediction logic:**
1. The 5th card's suit always equals card 1's suit.
2. The 5th card's rank = card 1's rank + an offset (1–6), wrapping modulo 13 (>14 wraps back).
3. The offset is encoded by the ordering of cards 2, 3, 4 by rank (suit breaks ties via CHaSeD):
   - Low/Med/High → 1, Low/High/Med → 2, Med/Low/High → 3
   - Med/High/Low → 4, High/Low/Med → 5, High/Med/Low → 6

**Call chain:** `revealFifth()` → `computeHiddenCard()` → `offsetFromCardOrder()` → `areCardsInOrder()` → `compare()` → `suit2number()`

The `offsetFromCardOrder()` function explicitly enumerates all 6 permutations for readability (not performance).
