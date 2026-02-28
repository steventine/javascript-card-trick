# JavaScript Card Trick

This is an implementation of the [Javascript Card Trick video](https://youtu.be/rkrjo4IIb1I) from  Dr Tim Muller  on [Computerphile](https://www.youtube.com/@Computerphile).

## Effect 
Spectator selects five cards at random from a deck, tells the computer about four of them, and the computer predicts the fifth.

## Method
Magician picks the order of the four cards given to the computer, thereby encoding the value of the fifth.

## Goal of This Project
The goal is to host Tim's original implementation on a published GitHub Page along with my version that has an enhanced UI/UX (with help from Cursor).

## Hosted GitHub Pages

My version with the enhanced UI/UX is available at [magic.tinefamily.com](https://magic.tinefamily.com)

Tim's original version is available at [magic.tinefamily.com/index_tim.html](https://magic.tinefamily.com/index_tim.html)

## 5th Card Logic

The suit of the 5th card matches the suit of the first card

The rank of the 5th card is incremented up from the rank of the first card based on the order of cards 2-5 (with Ace being high) and the CHaSeD suit order breaking ties (e.g. Diamonds is higher than Clubs):

* Offset of 1 -> Cards 2-5 are ordered:  `Low  - Med  - High`
* Offset of 2 -> Cards 2-5 are ordered:  `Low  - High - Med`
* Offset of 3 -> Cards 2-5 are ordered:  `Med  - Low  - High`
* Offset of 4 -> Cards 2-5 are ordered:  `Med  - High - Low`
* Offset of 5 -> Cards 2-5 are ordered:  `High - Low  - Med`
* Offset of 6 -> Cards 2-5 are ordered:  `High - Med  - Low`

Note: A is treated as low (i.e. value of 1) in determining the card order.

## Local development

Open `index.html` in a browser
