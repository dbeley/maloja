"""
Periodically follow a Last.fm user's scrobbles and import them into Maloja.

Uses the Last.fm API (user.getRecentTracks) to fetch recent scrobbles
and imports any new ones since the last check. The last imported timestamp
is stored in the database state for incremental imports.

Configuration:
  - follow_lastfm_username: Last.fm username to follow (string)
  - lastfm_api_key: Required API key for Last.fm API access
"""

import os
import datetime
import time as time_module
import requests

from doreah.logging import log

from ...cleanup import CleanerAgent

cla = CleanerAgent()

API_BASE = "https://ws.audioscrobbler.com/2.0/"

# Number of scrobbles to fetch per page (Last.fm max is 200)
PER_PAGE = 200


def follow_lastfm():
	"""Main entry point — called from server startup or CLI."""

	from ...pkg_global.conf import malojaconfig

	username = malojaconfig["FOLLOW_LASTFM_USERNAME"]
	api_key = malojaconfig["LASTFM_API_KEY"]

	if not username:
		log("follow_lastfm: No Last.fm username configured (follow_lastfm_username). Skipping.", color='cyan')
		return
	if not api_key:
		log("follow_lastfm: No Last.fm API key configured (lastfm_api_key). Skipping.", color='orange')
		return

	log(f"follow_lastfm: Checking for new scrobbles from Last.fm user '{username}'...", color='cyan')

	from ...database.sqldb import get_maloja_info, set_maloja_info

	# Read the last imported timestamp from database state
	last_ts_info = get_maloja_info(["lastfm_follow_last_ts"])
	last_timestamp = int(last_ts_info.get("lastfm_follow_last_ts", 0))

	all_new_scrobbles = []

	page = 1
	total_pages = 1

	while page <= total_pages:
		params = {
			"method": "user.getRecentTracks",
			"user": username,
			"api_key": api_key,
			"format": "json",
			"limit": PER_PAGE,
			"page": page,
			"extended": "1",
		}

		# Retry with exponential backoff on transient errors
		# (rate limiting, server glitches, etc.)
		max_retries = 5
		retry_delay = 2
		response = None
		data = None

		for attempt in range(1, max_retries + 1):
			try:
				response = requests.get(API_BASE, params=params, timeout=30)
				response.raise_for_status()
				data = response.json()
				break  # success, exit retry loop
			except requests.RequestException as e:
				status = response.status_code if response is not None else "N/A"
				if attempt < max_retries:
					log(f"follow_lastfm: Page {page} (attempt {attempt}/{max_retries}) — HTTP {status}: {e}. Retrying in {retry_delay}s...", color='orange')
					time_module.sleep(retry_delay)
					retry_delay *= 2  # exponential backoff: 2, 4, 8, 16, 32
				else:
					log(f"follow_lastfm: Page {page} — HTTP {status}: {e}. All {max_retries} retries exhausted, stopping.", color='red')
					data = None

		if data is None:
			break  # Could not fetch this page, import what we have so far

		if "recenttracks" not in data or "track" not in data["recenttracks"]:
			log(f"follow_lastfm: Unexpected API response for user '{username}'. Check the username.", color='red')
			return

		# Check for API errors
		if "error" in data:
			log(f"follow_lastfm: Last.fm API error: {data.get('message', 'unknown')}", color='red')
			return

		total_pages = int(data["recenttracks"].get("@attr", {}).get("totalPages", 1))
		tracks = data["recenttracks"]["track"]

		# Process tracks on this page
		new_count = 0
		reached_existing = False

		for track in tracks:
			# Currently scrobbling track has no date, skip it
			if "@attr" in track and track["@attr"].get("nowplaying") == "true":
				continue

			if "date" not in track or "uts" not in track["date"]:
				continue

			try:
				track_ts = int(track["date"]["uts"])
			except (ValueError, TypeError):
				continue

			# If this track is older or equal to our last import, stop
			if track_ts <= last_timestamp:
				reached_existing = True
				break

			artist = track.get("artist", {})
			if isinstance(artist, dict):
				artist_name = artist.get("name", "")
			else:
				artist_name = str(artist)

			title = track.get("name", "")
			album_info = track.get("album", {})
			if isinstance(album_info, dict):
				# Last.fm API uses #text without extended=1, or name with extended=1
				album_name = album_info.get("name") or album_info.get("#text", "")
			else:
				album_name = str(album_info)

			all_new_scrobbles.append({
				"time": track_ts,
				"track": {
					"artists": [artist_name],
					"title": title,
					"album": {
						"albumtitle": album_name,
						"artists": [artist_name],
					} if album_name else None,
					"length": None,
				},
				"duration": None,
				"origin": "import:lastfm_follow",
			})

			new_count += 1

		if new_count > 0:
			log(f"follow_lastfm: Page {page}/{total_pages}: {new_count} new scrobbles found")

		if reached_existing:
			break

		page += 1

	if not all_new_scrobbles:
		log("follow_lastfm: No new scrobbles found.")
		return

	# Import all new scrobbles to the database
	from ...database.sqldb import add_scrobbles, get_scrobbles_num

	newest_ts = max(s["time"] for s in all_new_scrobbles)

	# Sort by time ascending so the database receives them in order
	all_new_scrobbles.sort(key=lambda s: s["time"])

	log(f"follow_lastfm: Importing {len(all_new_scrobbles)} new scrobbles...", color='green')

	try:
		success, exists, errors = add_scrobbles(all_new_scrobbles)
		log(f"follow_lastfm: Imported {success} scrobbles ({exists} duplicates, {errors} errors)", color='green')

		# Update the last imported timestamp to the newest scrobble we imported
		set_maloja_info({"lastfm_follow_last_ts": str(newest_ts)})

		# Invalidate caches so the new scrobbles show up immediately
		from ...database import dbcache
		if hasattr(dbcache, 'cache'):
			size_before = len(dbcache.cache)
			dbcache.cache.clear()
			log(f"follow_lastfm: Cleared DB cache ({size_before} entries)", module="debug_performance")
		if hasattr(dbcache, 'entitycache'):
			entity_size = len(dbcache.entitycache)
			dbcache.entitycache.clear()
			log(f"follow_lastfm: Cleared entity cache ({entity_size} entries)", module="debug_performance")

	except Exception as e:
		log(f"follow_lastfm: Error importing scrobbles: {e}", color='red')
