# Demo talk track (about 90 seconds)

Record `./demo.sh` in a terminal at 120 columns. Three acts. Say the bold
lines, point at the output.

## Act 1: the agent cannot see its key (steps 1 to 3)

**"Two agents, one gateway, one provider. Here is what the agent sees."**
Point at `OCI_GENAI_API_KEY as seen by the agent : open… (60 chars)` and
`looks like a real OCI GenAI key : no`.

**"And yet it works."** Point at `HTTP 200:` and read the model's sentence.
"The proxy swapped the placeholder for the real key on the way out, for
this host only."

## Act 2: the fence holds whatever the model decides (step 4)

**"Now the agent tries three things."** Point at the three probe lines.
"Allowed request, allowed. Unlisted host: denied before a packet leaves.
Disallowed method on the allowed host: denied with a reason the agent can
read. Nothing in the agent's code made these decisions."

## Act 3: the kill switch (steps 5 to 6d)

**"The worker loop is chatting every five seconds. Watch it."**

**"Level one: lock down every sandbox on the gateway with one command."**
Point at `blocked after 2 s` and `blocked after 4 s`, then the worker log
flipping from `ok` to `BLOCKED`.

**"And it is reversible."** Point at `reachable after 8 s` and the model
saying it is still there.

**"Level two: take the credential away from one agent."** Point at
`oci-agent blocked after 0 s` next to `oci-agent-2 reachable`. "Surgical.
The other agent never noticed."

**"Level three: freeze it for forensics."** Point at `Stopped` next to
`Ready`.

## Close (step 7)

**"Every one of those decisions is an OCSF event."** Point at `NET:OPEN
[MED] DENIED` and `Policy reloaded successfully (global)`.

**"Same ladder, whatever the credential: an API key today, a signed
request or a platform identity with no key at all with the two open pull
requests."**
