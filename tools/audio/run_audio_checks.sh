#!/bin/sh
# Run from the project root. Set GODOT to the full Godot 4.7.1 executable.
set -eu
GODOT=${GODOT:-godot}
mkdir -p work/audio-qa
for test in audio_service_suite narrative_audio_suite audio_gameplay_suite settings_volume_interaction_test settings_motion_test game_cursor_suite opening_film_suite day_cycle_suite onboarding_goals_suite model_suite opening_story_suite; do
  "$GODOT" --headless --path . --audio-driver Dummy --rendering-method gl_compatibility --script "tests/$test.gd" -- --flow-qa > "work/audio-qa/$test.latest.log" 2>&1
  if grep -Eq '^(SCRIPT ERROR|FAIL )' "work/audio-qa/$test.latest.log"; then
    cat "work/audio-qa/$test.latest.log"; exit 1
  fi
  echo "$test passed"
done
