import { BedrockRuntimeClient, ConverseCommand } from "@aws-sdk/client-bedrock-runtime";

const client = new BedrockRuntimeClient();
const MODEL_ID = process.env.MODEL_ID ?? "anthropic.claude-3-haiku-20240307-v1:0";

// ---------------------------------------------------------------------------
// Algorithm (verbatim port from algorithm.js — Ace is low, ranks 1–13)
// ---------------------------------------------------------------------------

function suit2number(suit) {
  if (suit === "c") return 1;
  if (suit === "h") return 2;
  if (suit === "s") return 3;
  if (suit === "d") return 4;
  return 0;
}

function compare(rank1, suit1, rank2, suit2) {
  if (rank1 > rank2) return 1;
  if (rank2 > rank1) return 0;
  if (suit2number(suit1) > suit2number(suit2)) return 1;
  return 0;
}

function areCardsInOrder(rank1, suit1, rank2, suit2, rank3, suit3) {
  return compare(rank3, suit3, rank2, suit2) && compare(rank2, suit2, rank1, suit1);
}

function offsetFromCardOrder(rank2, suit2, rank3, suit3, rank4, suit4) {
  if (areCardsInOrder(rank2, suit2, rank3, suit3, rank4, suit4)) return 1;
  if (areCardsInOrder(rank2, suit2, rank4, suit4, rank3, suit3)) return 2;
  if (areCardsInOrder(rank3, suit3, rank2, suit2, rank4, suit4)) return 3;
  if (areCardsInOrder(rank4, suit4, rank2, suit2, rank3, suit3)) return 4;
  if (areCardsInOrder(rank3, suit3, rank4, suit4, rank2, suit2)) return 5;
  if (areCardsInOrder(rank4, suit4, rank3, suit3, rank2, suit2)) return 6;
  console.error("Offset unknown — duplicate card?");
  return 6;
}

function computeHiddenCard(rank1, suit1, rank2, suit2, rank3, suit3, rank4, suit4) {
  const offset = offsetFromCardOrder(rank2, suit2, rank3, suit3, rank4, suit4);
  let rank5 = rank1 + offset;
  if (rank5 > 13) rank5 = rank5 - 13;
  return { rank5, suit5: suit1 };
}

// ---------------------------------------------------------------------------
// Rank / suit conversion helpers
// ---------------------------------------------------------------------------

function parseRank(s) {
  if (s === "A") return 1;
  if (s === "J") return 11;
  if (s === "Q") return 12;
  if (s === "K") return 13;
  return parseInt(s, 10);
}

// Parse a natural-language card string like "Ace of Spades" or "three of hearts"
function parseCardString(s) {
  const lower = s.toLowerCase().trim();
  const ofIdx = lower.lastIndexOf(" of ");
  if (ofIdx === -1) throw new Error(`Cannot parse card: "${s}"`);
  const rankStr = lower.slice(0, ofIdx).trim();
  const suitStr = lower.slice(ofIdx + 4).trim();
  return { rank: parseRankStr(rankStr), suit: parseSuitStr(suitStr) };
}

function parseRankStr(s) {
  const words = { ace:1, two:2, three:3, four:4, five:5, six:6, seven:7, eight:8, nine:9, ten:10, jack:11, queen:12, king:13 };
  if (words[s] !== undefined) return words[s];
  if (s === "a") return 1;
  if (s === "j") return 11;
  if (s === "q") return 12;
  if (s === "k") return 13;
  const n = parseInt(s, 10);
  if (!isNaN(n) && n >= 2 && n <= 10) return n;
  throw new Error(`Unknown rank: "${s}"`);
}

function parseSuitStr(s) {
  if (s === "clubs"    || s === "club")    return "c";
  if (s === "hearts"   || s === "heart")   return "h";
  if (s === "spades"   || s === "spade")   return "s";
  if (s === "diamonds" || s === "diamond") return "d";
  throw new Error(`Unknown suit: "${s}"`);
}

function rankToName(rank) {
  if (rank === 1) return "Ace";
  if (rank === 11) return "Jack";
  if (rank === 12) return "Queen";
  if (rank === 13) return "King";
  return String(rank);
}

function suitToName(suit) {
  return { c: "Clubs", h: "Hearts", s: "Spades", d: "Diamonds" }[suit] ?? suit;
}

// ---------------------------------------------------------------------------
// Tool definition
// ---------------------------------------------------------------------------

const toolConfig = {
  tools: [{
    toolSpec: {
      name: "predict_fifth_card",
      description: "Given 4 cards in the magician's arranged order, compute the hidden 5th card.",
      inputSchema: {
        json: {
          type: "object",
          required: ["cards"],
          properties: {
            cards: {
              type: "array",
              minItems: 4,
              maxItems: 4,
              description: "Exactly 4 cards in the magician's order. Each card is a string like 'Ace of Spades', 'Three of Hearts', '10 of Clubs'.",
              items: { type: "string" }
            }
          }
        }
      }
    }
  }]
};

const system = [{
  text: "You are a typical IA chatbot that will be used in a magic trick. Speak briefly and confidently. " +
        "When a spectator names their four cards, call predict_fifth_card immediately. " +
        "Reveal the result in a single sentence as an AI chatbot would answer a question. Never explain the algorithm."
}];

// ---------------------------------------------------------------------------
// CORS headers
// ---------------------------------------------------------------------------

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};

// ---------------------------------------------------------------------------
// Lambda handler
// ---------------------------------------------------------------------------

export const handler = async (event) => {
  // Handle preflight
  if (event.requestContext?.http?.method === "OPTIONS" || event.httpMethod === "OPTIONS") {
    return { statusCode: 204, headers: CORS_HEADERS, body: "" };
  }

  let transcript;
  try {
    const body = typeof event.body === "string" ? JSON.parse(event.body) : event.body;
    transcript = body?.transcript;
    if (!transcript) throw new Error("Missing transcript");
  } catch (err) {
    return {
      statusCode: 400,
      headers: CORS_HEADERS,
      body: JSON.stringify({ error: "Bad request: " + err.message })
    };
  }

  const messages = [{ role: "user", content: [{ text: transcript }] }];

  try {
    let response = await client.send(new ConverseCommand({
      modelId: MODEL_ID,
      system,
      toolConfig,
      messages
    }));

    // Agentic loop — Claude may call the tool one or more times
    let lastPrediction = null;
    while (response.stopReason === "tool_use") {
      const assistantMsg = response.output.message;
      messages.push(assistantMsg);

      const toolResults = assistantMsg.content
        .filter(b => b.toolUse)
        .map(b => {
          console.log("Tool input from Claude:", JSON.stringify(b.toolUse.input));
          const cards = b.toolUse.input.cards.map((c, i) => {
            if (typeof c !== "string"){
              throw new Error(`Card ${i} is not a string: ${JSON.stringify(c)}`);
            }else{
              console.log(`Card ${i} is a string: ${c}`);
            }
            return parseCardString(c);
          });
          const [c1, c2, c3, c4] = cards;
          const result = computeHiddenCard(
            c1.rank, c1.suit,
            c2.rank, c2.suit,
            c3.rank, c3.suit,
            c4.rank, c4.suit
          );
          const prediction = `The next card is the ${rankToName(result.rank5)} of ${suitToName(result.suit5)}.`;
          console.log("Prediction:", prediction);
          lastPrediction = prediction;
          return {
            toolUseId: b.toolUse.toolUseId,
            content: [{ text: prediction }]
          };
        });

      messages.push({
        role: "user",
        content: toolResults.map(r => ({ toolResult: r }))
      });

      response = await client.send(new ConverseCommand({
        modelId: MODEL_ID,
        system,
        toolConfig,
        messages
      }));
    }

    // Use the algorithmically-computed prediction directly to avoid Claude
    // hallucinating a different card when rephrasing the tool result.
    const text =
      lastPrediction ??
      response.output.message.content.find(b => b.text)?.text ??
      "I can't believe that I'm going to say this, but I don't know..";

    return {
      statusCode: 200,
      headers: CORS_HEADERS,
      body: JSON.stringify({ text, audio: null })
    };

  } catch (err) {
    console.error("Bedrock error:", err);
    return {
      statusCode: 500,
      headers: CORS_HEADERS,
      body: JSON.stringify({ error: "Prediction failed: " + err.message })
    };
  }
};
