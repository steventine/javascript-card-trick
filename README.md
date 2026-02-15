# JavaScript Card Trick

This is an implementation of the [Javascript Card Trick video](https://youtu.be/rkrjo4IIb1I) from  Dr Tim Muller  on [Computerphile](https://www.youtube.com/@Computerphile).

The goal is to host his original implementation on a published GitHub Page along with an enhanced UI/UX (with help from Cursor).

## Hosted GitHub Page

My version with the enhanced UI/UX is available at [magic.tinefamily.com](https://magic.tinefamily.com)

Tim's original version is available at [index_tim.html](https://magic.tinefamily.com/index_tim.html)

## 5th Card Logic

The suit of the 5th card matches the suit of the first card

The rank of the 5th card is incremented up from the rank of the first card based on the order of cards 2-5 (L=Lowest card, M=Middle card, H=Highest card):

* Offset of 1 -> Cards 2-5 are ordered L-M-H
* Offset of 2 -> Cards 2-5 are ordered L-H-M
* Offset of 3 -> Cards 2-5 are ordered M-L-H
* Offset of 4 -> Cards 2-5 are ordered M-H-L
* Offset of 5 -> Cards 2-5 are ordered H-L-M
* Offset of 6 -> Cards 2-5 are ordered H-M-L

## Local development

Open `index.html` in a browser
