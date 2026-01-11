Analyze this voice memo transcript and return a JSON object with exactly these fields:

- title: a concise descriptive title (3-7 words)
- summary: a 1-2 sentence summary of the main points
- tags: an array of 2-4 relevant topic tags (single words, lowercase, no # symbol)
- todos: an array of task objects extracted from the transcript. Each task object should have:
  - task: the task description (clear, actionable)
  - priority: one of "asap", "today", "thisweek", "thismonth", "thisyear" based on urgency mentioned or implied

If no todos are found, return an empty array for todos.

Return ONLY valid JSON, no other text.

Transcript:
