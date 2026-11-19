#!/usr/bin/env bash
# Completion notification for the PIPELINE_COMPLETION port
# (nf-core/fetchngs 1.13.0 workflow.onComplete + workflow.onError -> the
# [workflow] on_complete / on_error terminal hooks, engine >= 0.17.0):
#   - status        completed | failed
#   - email         completion summary recipient (config.email)
#   - email_on_fail failure summary recipient (config.email_on_fail)
#   - counters      {succeeded} {failed} {skipped}, the run's rule counts
#   - out_dir       {config.out_dir}
#
# Usage: pipeline_completion.sh <status> <email> <email_on_fail> \
#        <succeeded> <failed> <skipped> <out_dir>
#
# Upstream 1.13.0 removed the hook_url / imNotification feature (the webhook
# JSON-card support of 1.12.0 was dropped together with assets/adaptivecard.json
# and assets/slackreport.json), so this port carries no webhook branch either.
# The upstream workflow.onError branch logs the troubleshooting hint; the
# same line is emitted here on the failed path.
#
# Best-effort by contract: always exits 0. A missing mail tool only warns —
# a notification must never change the run status.
set -u

status="$1"
email="$2"
email_on_fail="$3"
succeeded="$4"
failed="$5"
skipped="$6"
out_dir="$7"

# Upstream workflow.onError (1.13.0): log the troubleshooting hint on failed
# runs, independent of the email configuration.
if [ "$status" = "failed" ]; then
    echo "Pipeline failed. Please refer to troubleshooting docs for common issues: https://nf-co.re/docs/running/troubleshooting" >&2
fi

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
    body="nf-core/fetchngs 1.13.0 (oxo-flow port) ${status}.

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

exit 0
