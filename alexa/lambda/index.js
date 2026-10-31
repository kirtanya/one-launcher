// One TV: "Alexa, ask One TV to search Panchayat" / "… to search Dune on YouTube" / "… to open YouTube".
// Posts the words to a secret ntfy.sh topic; One Launcher TV listens there (AlexaRelay.kt).
// Template: alexa/make.sh writes alexa/out/index.js with the real topic (never commit that one).
const https = require('https');

const TOPIC = '__ALEXA_TOPIC__';

function send(msg) {
  return new Promise((resolve) => {
    const body = JSON.stringify(msg);
    const req = https.request(
      { host: 'ntfy.sh', path: '/' + TOPIC, method: 'POST', headers: { 'Content-Type': 'text/plain', 'Content-Length': Buffer.byteLength(body) }, timeout: 4000 },
      (res) => { res.resume(); resolve(res.statusCode === 200); },
    );
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
    req.end(body);
  });
}

// "dune on netflix" heard as one search: split the app off the end (only names we know, so
// "murder on the orient express" stays whole).
const APPS = /\s+(?:on|in)\s+(you ?tube(?: music)?|net ?flix|(?:amazon )?prime(?: video)?|amazon video|(?:jio |disney )?hot ?star|jio ?hotstar|jio cinema|one ?stream|nuvio|zee ?(?:5|five)|sony ?liv)$/i;
function splitApp(q) {
  const m = q.match(APPS);
  return m ? { q: q.slice(0, m.index).trim(), app: m[1] } : { q, app: '' };
}

function say(text, keepOpen) {
  return {
    version: '1.0',
    response: {
      outputSpeech: { type: 'PlainText', text },
      ...(keepOpen ? { reprompt: { outputSpeech: { type: 'PlainText', text: 'Say search, then a name. Or open, then an app.' } } } : {}),
      shouldEndSession: !keepOpen,
    },
  };
}

exports.handler = async (event) => {
  const req = event.request || {};
  if (req.type === 'LaunchRequest') return say('What should I find on the TV?', true);
  if (req.type !== 'IntentRequest') return say('', false);
  const intent = req.intent || {};
  const slot = (n) => ((intent.slots || {})[n] || {}).value || '';
  switch (intent.name) {
    case 'SearchIntent':
    case 'SearchOnIntent': {
      let q = slot('query').trim();
      let app = slot('app').trim();
      if (!app) ({ q, app } = splitApp(q));
      if (!q) return say('What should I search for?', true);
      const where = app ? ` on ${app}` : '';
      return (await send({ type: 'search', q, ...(app ? { app } : {}) })) ? say(`Searching ${q}${where}.`) : say('I couldn’t reach the TV.');
    }
    case 'OpenIntent': {
      const app = slot('app').trim();
      if (!app) return say('Which app?', true);
      return (await send({ type: 'open', app })) ? say(`Opening ${app}.`) : say('I couldn’t reach the TV.');
    }
    case 'AMAZON.HelpIntent':
      return say('Say: search Panchayat. Or: search Dune on YouTube. Or: open Netflix.', true);
    case 'AMAZON.FallbackIntent':
      return say('Say search, then a name. Or open, then an app.', true);
    default:
      return say('Okay.');
  }
};
