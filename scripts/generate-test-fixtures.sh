#!/usr/bin/env bash
# generate-test-fixtures.sh — Create 500 realistic note files for benchmarking.
#
# Usage: ./scripts/generate-test-fixtures.sh [OUTPUT_DIR]
#   OUTPUT_DIR defaults to a temp directory; the path is printed to stdout.
#
# Creates files with:
#   - 3 file types: .md (60%), .txt (25%), .org (15%)
#   - Varying lengths: tiny (1–5 lines), small (10–30), medium (50–150), large (300–800)
#   - Subdirectories to simulate a real notes folder
#   - Realistic titles, tags, and body content
#   - The "Meeting Notes" file is always included (benchmark target)

set -euo pipefail

DIR="${1:-$(mktemp -d -t NeoNVFixtures)}"
mkdir -p "$DIR"

# ── Word / sentence pools ──────────────────────────────────────────────
NOUNS=(project meeting design review sprint backlog deployment pipeline
       architecture database migration refactor documentation testing
       release roadmap retrospective standup brainstorm onboarding
       security compliance monitoring alerting dashboard analytics
       budget forecast hiring interview feedback performance growth
       strategy vision mission values culture innovation research
       prototype experiment hypothesis analysis synthesis evaluation
       planning scheduling coordination communication collaboration
       automation integration optimization scalability reliability)

VERBS=(implement deploy review analyze discuss plan evaluate test
       monitor optimize refactor document integrate automate scale
       design build ship iterate prototype research explore validate
       prioritize schedule coordinate communicate collaborate migrate
       configure provision debug troubleshoot investigate benchmark)

ADJECTIVES=(quick important urgent critical essential fundamental
            comprehensive detailed thorough systematic structured
            innovative creative strategic operational tactical
            preliminary final interim quarterly monthly weekly daily
            upcoming pending completed ongoing recurring temporary
            high-priority low-priority medium-priority blocked)

TOPICS=(engineering product design marketing sales operations finance
        infrastructure security devops platform frontend backend
        mobile api data machine-learning cloud networking storage
        authentication authorization payments notifications search
        onboarding analytics reporting compliance legal hr recruiting)

TAGS_MD=("#work" "#personal" "#todo" "#idea" "#reference" "#draft"
         "#meeting" "#project" "#research" "#review" "#important"
         "#followup" "#archived" "#weekly" "#monthly")

TAGS_ORG=(work personal todo idea reference draft meeting project
          research review important followup archived weekly monthly)

# ── Helpers ────────────────────────────────────────────────────────────
pick() { local arr=("$@"); echo "${arr[$((RANDOM % ${#arr[@]}))]}" ; }

random_range() { echo $(( $1 + RANDOM % ($2 - $1 + 1) )); }

random_sentence() {
    local adj=$(pick "${ADJECTIVES[@]}")
    local noun=$(pick "${NOUNS[@]}")
    local verb=$(pick "${VERBS[@]}")
    local topic=$(pick "${TOPICS[@]}")
    # Vary sentence structure
    case $((RANDOM % 5)) in
        0) echo "We need to $verb the $adj $noun for $topic." ;;
        1) echo "The $topic team will $verb the $noun by next week." ;;
        2) echo "Consider a $adj approach to $verb the $noun." ;;
        3) echo "Action item: $verb $noun ($adj priority, $topic)." ;;
        4) echo "Discussion about $adj $noun in the context of $topic." ;;
    esac
}

random_paragraph() {
    local sentences=$(random_range 3 8)
    local para=""
    for ((s=0; s<sentences; s++)); do
        para+="$(random_sentence) "
    done
    echo "$para"
}

random_list_items() {
    local count=$(random_range 3 10)
    for ((i=0; i<count; i++)); do
        local noun=$(pick "${NOUNS[@]}")
        local verb=$(pick "${VERBS[@]}")
        case $((RANDOM % 3)) in
            0) echo "- [ ] $(pick "${ADJECTIVES[@]}") $noun: $verb" ;;
            1) echo "- [x] $verb the $noun" ;;
            2) echo "- $noun — $(random_sentence)" ;;
        esac
    done
}

generate_body() {
    local target_lines=$1
    local lines=0
    local body=""

    while (( lines < target_lines )); do
        case $((RANDOM % 4)) in
            0)  # Paragraph
                body+="$(random_paragraph)"$'\n\n'
                lines=$((lines + 3))
                ;;
            1)  # Heading + paragraph
                body+="## $(pick "${ADJECTIVES[@]}") $(pick "${NOUNS[@]}")"$'\n\n'
                body+="$(random_paragraph)"$'\n\n'
                lines=$((lines + 5))
                ;;
            2)  # List
                body+="$(random_list_items)"$'\n\n'
                lines=$((lines + 6))
                ;;
            3)  # Code block
                body+='```'$'\n'
                body+="func $(pick "${VERBS[@]}")$(pick "${NOUNS[@]}")() {"$'\n'
                body+="    // $(random_sentence)"$'\n'
                body+="    let result = process($(pick "${NOUNS[@]}"))"$'\n'
                body+="    return result"$'\n'
                body+="}"$'\n'
                body+='```'$'\n\n'
                lines=$((lines + 8))
                ;;
        esac
    done
    echo "$body"
}

# ── Subdirectories ─────────────────────────────────────────────────────
SUBDIRS=("" "" "" "" ""  # 50% in root
         "projects" "projects" "projects"
         "daily" "daily" "daily" "daily"
         "meetings" "meetings"
         "ideas"
         "archive" "archive"
         "reference"
         "work/engineering" "work/product" "work/design"
         "personal" "personal/journal")

# ── Generate files ─────────────────────────────────────────────────────

# Always include the benchmark target file
cat > "$DIR/meeting-notes.md" << 'EOF'
# Meeting Notes

Agenda items for the weekly sync.

## Topics

- Project status update
- Sprint planning review
- Action items from last week

## Notes

The team discussed the upcoming release timeline and agreed on priorities.
EOF

count=1  # meeting-notes.md already created

for i in $(seq 2 500); do
    # Pick file type
    type_roll=$((RANDOM % 100))
    if (( type_roll < 60 )); then
        ext="md"
    elif (( type_roll < 85 )); then
        ext="txt"
    else
        ext="org"
    fi

    # Pick size category
    size_roll=$((RANDOM % 100))
    if (( size_roll < 30 )); then
        target_lines=$(random_range 1 5)      # tiny
    elif (( size_roll < 60 )); then
        target_lines=$(random_range 10 30)     # small
    elif (( size_roll < 85 )); then
        target_lines=$(random_range 50 150)    # medium
    else
        target_lines=$(random_range 300 800)   # large
    fi

    # Pick subdirectory
    subdir=$(pick "${SUBDIRS[@]}")
    if [[ -n "$subdir" ]]; then
        mkdir -p "$DIR/$subdir"
    fi

    # Generate unique filename
    noun1=$(pick "${NOUNS[@]}")
    noun2=$(pick "${NOUNS[@]}")
    adj=$(pick "${ADJECTIVES[@]}")
    filename="${adj}-${noun1}-${noun2}-${i}.${ext}"
    filepath="$DIR"
    [[ -n "$subdir" ]] && filepath="$DIR/$subdir"

    # Generate content based on file type
    case "$ext" in
        md)
            title="# $(echo "$adj $noun1 $noun2" | sed 's/\b\(.\)/\u\1/g' 2>/dev/null || echo "$adj $noun1 $noun2")"
            tags=""
            if (( RANDOM % 3 == 0 )); then
                t1=$(pick "${TAGS_MD[@]}")
                t2=$(pick "${TAGS_MD[@]}")
                tags="Tags: $t1, $t2"$'\n\n'
            fi
            body=$(generate_body "$target_lines")
            echo -e "${title}\n\n${tags}${body}" > "$filepath/$filename"
            ;;
        txt)
            title="$(echo "$adj $noun1 $noun2" | sed 's/\b\(.\)/\u\1/g' 2>/dev/null || echo "$adj $noun1 $noun2")"
            body=$(generate_body "$target_lines")
            echo -e "${title}\n\n${body}" > "$filepath/$filename"
            ;;
        org)
            title="#+TITLE: $(echo "$adj $noun1 $noun2" | sed 's/\b\(.\)/\u\1/g' 2>/dev/null || echo "$adj $noun1 $noun2")"
            filetags=""
            if (( RANDOM % 3 == 0 )); then
                t1=$(pick "${TAGS_ORG[@]}")
                t2=$(pick "${TAGS_ORG[@]}")
                filetags="#+FILETAGS: :${t1}:${t2}:"$'\n'
            fi
            # Convert markdown-style body to org-style
            body=$(generate_body "$target_lines" | sed 's/^## /* /; s/^- \[x\]/- DONE/; s/^- \[ \]/- TODO/')
            echo -e "${title}\n${filetags}\n${body}" > "$filepath/$filename"
            ;;
    esac

    count=$((count + 1))
done

echo "$DIR"
echo "Generated $count fixture files in $DIR" >&2
