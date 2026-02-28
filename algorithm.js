// Use the suit of the card1 and add the calculated offset to the rank of the card1
function computeHiddenCard(rank1, suit1, rank2, suit2, rank3, suit3, rank4, suit4) {
  var offset = offsetFromCardOrder(rank2, suit2, rank3, suit3, rank4, suit4);
  var rank5 = rank1 + offset;

  // Loop around if the rank is greater than King (Ace is low, so ranks are 1–13)
  if (rank5 > 13) rank5 = rank5 - 13;
  return { rank5: rank5, suit5: suit1 };
}

// The offset is based on the order of cards2-4:
//    Card2, Card3, Card4
//    -----  -----  -----
// 1: Low,   Med,   High
// 2: Low,   High,  Med
// 3: Med,   Low,   High
// 4: Med,   High,  Low
// 5: High,  Low,   Med
// 6: High,  Med,   Low
function offsetFromCardOrder(rank2, suit2, rank3, suit3, rank4, suit4) {
  //This is the least efficient way to do this, but it is the most readable.
  if(areCardsInOrder(rank2, suit2, rank3, suit3, rank4, suit4)){
    // 2 < 3 < 4
    // Low, Med, High
    return 1;
  }else if(areCardsInOrder(rank2, suit2, rank4, suit4, rank3, suit3)){
    // 2 < 4 < 3
    // Low, High, Med
    return 2;
  }else if(areCardsInOrder(rank3, suit3, rank2, suit2, rank4, suit4)){
    // 3 < 2 < 4
    // Med, Low, High
    return 3;
  }else if(areCardsInOrder(rank4, suit4, rank2, suit2, rank3, suit3)){
    // 4 < 2 < 3
    // Med, High, Low
    return 4;
  }else if(areCardsInOrder(rank3, suit3, rank4, suit4, rank2, suit2)){
    // 3 < 4 < 2
    // High, Low, Med
    return 5;
  }else if(areCardsInOrder(rank4, suit4, rank3, suit3, rank2, suit2)){
    // 4 < 3 < 2
    // High, Med, Low
    return 6;
  }else{
    //SHOULD ONLY HAPPEN IF TWO CARDS ARE THE SAME RANK AND SUIT
    console.error("Offset is unknown...are two cards the same rank and suit?");
    return 6;
  }
}

// Return true if the cards are in order (lowest to highest), false otherwise
function areCardsInOrder(rank1, suit1, rank2, suit2, rank3, suit3) {
  return compare(rank3, suit3, rank2, suit2) && compare(rank2, suit2, rank1, suit1);
}

// Return 1 if card1 is greater than card2, else 0
function compare(rank1, suit1, rank2, suit2) {
  if (rank1 > rank2) return 1;
  if (rank2 > rank1) return 0;
  if (suit2number(suit1) > suit2number(suit2)) return 1;
  return 0;
}

// If the ranks of two cards are the same, use the suit to determine the order
// Use "CHaSeD" order
function suit2number(suit) {
  if (suit === "c") return 1;
  if (suit === "h") return 2;
  if (suit === "s") return 3;
  if (suit === "d") return 4;
  return 0;
}
