# Content schema (contract between content files and the Swift app)

All content ships as JSON in `ios/System/Resources/Content/`, decoded with Swift `Codable`
(camelCase keys, no nulls: omit optional keys). IDs are kebab-case and stable forever.

Pillars: `body`, `mind`, `social`, `sovereign`.
Stats: `STR` `END` `AGI` `VIT` (body) · `PER` `INT` `WIL` (mind) · `CHA` (social) · `SOV` (sovereign).
Difficulty: integer 1-5 (1 = E-rank beginner, 5 = S-rank). Cadence: `daily` `weekly` `monthly`.

## challenges.json  (from The Sovereign's Education + social/mental practice)
{ "version": 1, "challenges": [ {
  "id": "s4-state-reset-breath",
  "title": "Box Breath Reset",            // <= 40 chars, imperative
  "pillar": "mind",
  "stat": "WIL",
  "cadence": "daily",
  "difficulty": 1,
  "minutes": 5,
  "instructions": "Concrete, doable steps. 1-4 sentences. What counts as done.",
  "why": "One sentence on the principle, in plain words.",
  "source": "S4.5 State Management",       // corpus section, or "general"
  "proof": "check" | "note" | "count"       // how completion is logged
} ] }

## lessons-poker.json / lessons-chess.json / lessons-go.json
{ "version": 1, "game": "poker"|"chess"|"go", "units": [ {
  "id": "chess-u1-board", "title": "...", "order": 1, "difficulty": 1,
  "lessons": [ {
    "id": "chess-u1-l1", "title": "...",
    "body": "Markdown, 80-300 words.",
    "quiz": [ {
      "prompt": "...",
      "choices": ["A","B","C","D"],      // multiple choice
      "answer": 0,                         // index into choices
      "explain": "1-2 sentences"
    } ],
    "puzzles": [ {                         // optional, chess/go only
      "id": "...",
      "position": "FEN (chess) or go-9x9 string (go)",
      "toMove": "w"|"b",
      "solution": ["e2e4","e7e5"],         // chess UCI moves; go: "d4" style coords, alternating, starting with toMove
      "goal": "Mate in 1" ,
      "rating": 800
    } ]
  } ]
} ] }

Go position string: 9 rows from row 9 (top) to row 1 (bottom), separated by "/", each row 9 chars:
`.` empty, `b` black, `w` white. Coordinates: columns a-j skipping i, rows 1-9 (e.g. "e5").
All v1 go puzzles are 9x9.

## training.json  (beginner programme, authored in-app repo)
Phases of weeks; sessions list exercises with sets x rep range, rest, and progression rule
"double-progression": add load when top of range is hit for 2 consecutive sessions.
