#!/usr/bin/env bash
# Completion notification for the PIPELINE_COMPLETION port
# (nf-core/fetchngs 1.12.0 workflow.onComplete -> the [workflow]
# on_complete / on_error terminal hooks, engine >= 0.17.0):
#   - status        completed | failed
#   - email         completion summary recipient (config.email)
#   - email_on_fail failure summary recipient (config.email_on_fail)
#   - hook_url      webhook URL for the JSON notification (config.hook_url)
#   - counters      {succeeded} {failed} {skipped}, the run's rule counts
#   - out_dir       {config.out_dir}
#
# Usage: pipeline_completion.sh <status> <email> <email_on_fail> <hook_url> \
#        <succeeded> <failed> <skipped> <out_dir>
#
# Best-effort by contract: always exits 0. Missing mail tools or a failing
# webhook only warn — a notification must never change the run status.
set -u

status="$1"
email="$2"
email_on_fail="$3"
hook_url="$4"
succeeded="$5"
failed="$6"
skipped="$7"
out_dir="$8"

# nf-core sends the failure mail to email_on_fail (and to email when only
# that is set); on completion the recipient is always email. Both hooks
# pass both addresses, so pick here.
if [ "$status" = "failed" ] && [ -n "$email_on_fail" ]; then
    recipient="$email_on_fail"
else
    recipient="$email"
fi

send_mail() {
    local mail_to="$1"
    local subject body
    subject="[fetchngs] ${status}: ${succeeded} succeeded, ${failed} failed, ${skipped} skipped"
    body="nf-core/fetchngs 1.12.0 (oxo-flow port) ${status}.

Rules: ${succeeded} succeeded, ${failed} failed, ${skipped} skipped.
Results: ${out_dir}"

    if command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $mail_to"
            echo "Subject: $subject"
            echo
            echo "$body"
        } | sendmail -t
    elif command -v mail >/dev/null 2>&1; then
        printf '%s\n' "$body" | mail -s "$subject" "$mail_to"
    else
        echo "WARNING: completion mail to $mail_to not sent (neither 'sendmail' nor 'mail' available)" >&2
    fi
}

if [ -n "$recipient" ]; then
    send_mail "$recipient"
fi

if [ -n "$hook_url" ]; then
    # Upstream imNotification posts a JSON card (Slack / Adaptive Cards)
    # with the run summary; here the payload carries the run counters.
    # Quiet on success; a failing notification only warns (best-effort).
    # The URL itself is never echoed, so webhook credentials cannot leak.
    curl -fsS -m 30 -X POST -H 'Content-Type: application/json' \
        -d "{\"text\":\"[fetchngs] run ${status}: ${succeeded} succeeded, ${failed} failed, ${skipped} skipped\"}" \
        "$hook_url" >/dev/null 2>&1 \
        || echo "WARNING: webhook notification not delivered" >&2
fi

exit 0
