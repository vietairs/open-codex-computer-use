# [2026-04-22 14:59] | Task: Clarify the default reply language for English input

## 📥 User Query
> add in Agent.md, if user input in english, reply in english

## 🛠 Changes Overview
- Added an explicit constraint to the working rules in `AGENTS.md`: if the user's input in this turn is in English, reply in English.
- Kept the existing repo-level collaboration rule of "default to mirroring the language of the user's question, switch reply language if they switch language," while writing the English-input case as a more direct, explicit rule to reduce ambiguity in future execution.

## 🧠 Design Intent
- This kind of collaboration constraint should land directly in the repo's entry-point doc, rather than relying on session memory.
- Making the English-input case explicit means future agents no longer need to infer it from the generalized rule, making execution more stable.

## 📁 Files Touched
- `AGENTS.md`
