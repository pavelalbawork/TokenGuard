# TokenGuard — Next Steps

## Immediate Priority

1. Verify provider research with official sources
2. Decide which providers are actually V1-worthy
3. Lock the minimum viable popover/account-card design
4. Write one architecture decision record
5. Only then create a fresh implementation brief

## Suggested Order

### Step 1: Provider verification

For each provider, answer:

- What is the actual source of truth?
- Is it stable?
- Does it expose:
  - usage
  - hard limit
  - reset date
  - plan/tier
- Is multi-account realistic?

### Step 2: Product shaping

Decide:

- V1 providers
- V1 data fields
- V1 states
- V1 account model

### Step 3: Architecture

Lock only:

- persistence model
- Keychain boundaries
- refresh model
- data freshness/error states

### Step 4: Implementation kickoff

Create a new implementation brief after the earlier steps are done. Treat the current Swift model files as exploratory unless they survive the architecture pass unchanged.
