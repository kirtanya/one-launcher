# One TV: Alexa skill for One Launcher TV

"Alexa, ask One TV to search Panchayat" → One Launcher TV opens its search with those words.
"Alexa, ask One TV to open YouTube" → opens the installed app with that name (else searches it).
"Alexa, ask One TV to search Dune on YouTube" → YouTube's own results. The same without "on …"
searches inside the app on screen when it can (YouTube only, on the Acer); Netflix, Prime Video and
JioHotstar take no searches from other apps, so those land in One Launcher's search (their rows +
"Watch on …").

How it works: Alexa → this skill (hosted free by Amazon) → a secret ntfy.sh topic → the TV
(`AlexaRelay.kt`, one streaming connection, started by TvActivity and ShowNameService). Searched
words pass through Amazon and ntfy.sh; whoever knows the topic can send searches to the TV, so
it's long and random and never committed.

## Files
- `interaction-model.json`: what Alexa listens for (invocation "one tv"; search / open).
- `lambda/index.js`: the skill's code, with a placeholder topic.
- `make.sh`: makes `../alexa.topic` once and `out/index.js` (the code with the real topic).
  The TV build reads `alexa.topic` (Gradle → `R.string.alexa_topic`; empty = off).

## One-time setup (in the browser, on your Amazon account)
1. developer.amazon.com/alexa/console/ask → sign in with the same Amazon account as the Echo.
2. Create Skill → name "One TV", locale **English (IN)** (the Echo's language), type **Other** →
   **Custom** model → **Alexa-hosted (Node.js)** → template **Start from scratch** → create.
3. Build tab → Interaction Model → **JSON Editor** → paste `interaction-model.json` → Save → **Build skill**.
4. Code tab → replace `lambda/index.js` with `out/index.js` → **Save** → **Deploy**.
5. Test tab → set "Skill testing is enabled in" to **Development** → type
   "ask one tv to search panchayat" → the TV should open search.

Development mode is enough: it works on every Echo signed in to this account; no certification.
After the interaction model changes: Build tab → JSON Editor → paste again → Build skill; after
`lambda/index.js` changes: run `make.sh`, Code tab → paste `out/index.js` → Save → Deploy.
New topic: delete `alexa.topic`, run `make.sh`, paste `out/index.js` again, rebuild the TV app.
