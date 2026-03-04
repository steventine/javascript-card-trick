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

## Voice Interface (`voice.html`)

A voice-driven version powered by AWS Lambda + Amazon Bedrock (Claude 3 Haiku). The performer speaks four cards aloud; Zarcon the AI magician predicts the hidden fifth.

### Architecture

```
Phone mic → Web Speech API → voice.html
  → POST transcript → API Gateway → Lambda (Node.js 20)
    → Bedrock ConverseCommand (Claude 3 Haiku) with tool
    → Lambda runs card algorithm → returns prediction
  → voice.html speaks response via browser TTS
```

### Prerequisites

- AWS CLI configured (`aws configure`)
- Node.js 20+ via nvm (`nvm use 20`)
- `zip` (`sudo apt install zip`)

### Deploy

```bash
./scripts/deploy.sh
```

The script is safe to re-run. It will:

1. `npm install` the Lambda dependencies and zip the package
2. Create an IAM role with Bedrock + Lambda execution permissions
3. Create or update the Lambda function (Node.js 20, 256 MB, 30 s timeout)
4. Create an API Gateway HTTP API with CORS configured for `magic.tinefamily.com`
5. Patch `voice.html` with the live API endpoint URL

**One manual step:** Enable Bedrock model access in the AWS Console before invoking the function. The deploy script prints the direct link when it finishes.

### Local testing

Browsers block API calls from `file://` URLs. Serve the page locally instead:

```bash
python3 -m http.server 8080
# then open http://localhost:8080/voice.html
```

### Test

```bash
curl -X POST <endpoint printed by deploy.sh> \
  -H 'Content-Type: application/json' \
  -d '{"transcript":"Ace of spades, three of hearts, jack of clubs, seven of diamonds"}'
# Expected: {"text":"...dramatic prediction...","audio":null}
```

### Teardown

```bash
./scripts/teardown.sh
```

Deletes the Lambda function, IAM role, API Gateway, and local build artifacts. Restores the placeholder URL in `voice.html`.
