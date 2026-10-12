#!/bin/bash
# GitHub-side settings for RodRedRiver/impkt-ios. Run by the owner after review;
# nothing in the repository runs it.
#
# The repository is already public, so there is no `gh repo create` here. The
# branch this was prepared on (profile-polish) has to be pushed and merged into
# main first, by hand, after approval:
#
#   # APPROVAL REQUIRED
#   # git push -u origin profile-polish      # then open the pull request and merge it
#
# Everything below only writes the description, homepage and topics, prints each
# command as it runs, and is safe to run again.
set -euo pipefail
set -x

gh repo edit RodRedRiver/impkt-ios \
  --description "iOS app for the IMPKT boxing wearable: the pilot web page on CoreBluetooth, a gym leaderboard, and firmware updates over Nordic DFU from the phone." \
  --homepage "https://impktband.com" \
  --add-topic ios \
  --add-topic swift \
  --add-topic swiftui \
  --add-topic bluetooth-le \
  --add-topic corebluetooth \
  --add-topic nordic-dfu \
  --add-topic wearable \
  --add-topic xcodegen
