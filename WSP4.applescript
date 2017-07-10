-- Copyright 2017 Maximilian Montserrat, email me at maximthemagnificent@gmail.com with any questions, comments, suggestions, etc.
-- Note that efficiency was deliberately sacrificed for clarity.

-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
-- files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy,
-- modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom
-- the Software is furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
-- OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
-- LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
-- IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.



-- user control parameters
property OUTPUT_PLAYLIST_NAME : "WSP output" -- name of playlist to add output songs to
property OUTPUT_SIZE : 950 -- desired size, in MB of output playlist (will always be smaller than this limit)
property UNTRIED_SONG_FRACTION : 0.1 -- fraction of output to set to untried songs (if not enough tried ones, this could be larger)
property RATING_REPEAT_INTERVAL : 7 -- repeat interval, in days, per rating tick (r = 100: 1 * interval, r = 99: 2 * interval, etc.   r = 1: 100 * interval, note r = 0 means unrated )
property SKIP_LEARN_RATE : 0.9 -- when skipped, new rating is set to old_rating + (new_rating-old_rating) * skip_learn_rate
property PLAY_LEARN_RATE : 0.3 -- when played, new rating is set to old_rating + (new_rating-old_rating) * play_learn_rate
property PLAYED_FIRST_TIME_RATING : 100 -- since there's no time period the first time a song is attempted, what rating do I use if it's played?
property SKIPPED_FIRST_TIME_RATING : 90 -- since there's no time period the first time a song is attempted, what rating do I use if it's skipped?

-- advanced control parameters; not much reason to adjust these
property TRIED_SONGS : "WSP test" -- Change to "WSP4 Tried" after debugging				-- playlist of songs with previous attempts (play & skip dates give us soemthing to work with)
property UNTRIED_SONGS : "WSP4 Untried" -- songs that have never been attempted (no play & skip dates)
property MISSING_VALUE_DATE : "1/1/1990"

property TOTAL_SIZE_TARGET : OUTPUT_SIZE * 1024 * 1024



-- create date from iTunes value, checking if it is invalid and, if so, returning one far in the past instead to simplify comparisons
on GetDate(itunes_date)
	if (itunes_date as string) is equal to "missing value" then
		return date (MISSING_VALUE_DATE)
	else
		return itunes_date
	end if
end GetDate



-- song class, copntains play pressure information for tracks
on createSong(track, last_attempted_date)
	
	script Song
		property itunes_track : null -- iTunes song
		property size : null -- size of song
		property play_pressure : null -- pressure for being played
	end script
	
	-- constructor
	tell Song
		
		set itunes_track to track
		
		using terms from application "iTunes"
			
			set size to size of track
			set rating to rating of track
			
		end using terms from
		
		set elapsed_time to currDate - last_attempted_date
		set multiplier to RATING_REPEAT_INTERVAL * (101 - rating)
		set play_pressure to elapsed_time / multiplier
	end tell
	
	return Song
	
end createSong



-- write songs to output playlist
on WriteSongs(output_songs)
	
	tell application "iTunes"
		
		-- clear output playlist
		if user playlist OUTPUT_PLAYLIST_NAME exists then
			try
				delete tracks of user playlist OUTPUT_PLAYLIST_NAME
			end try
		else
			make new user playlist with properties {name:OUTPUT_PLAYLIST_NAME}
		end if
		
		
		-- add tracks to output playlist
		repeat with aTrack in output_songs
			duplicate aTrack to playlist OUTPUT_PLAYLIST
		end repeat
		
	end tell
	
end WriteSongs



-- get songs that have never been attempted before
on GetUntriedSongs(songs)
	
	-- compute amount of untried songs to add
	set untried_target_size to TOTAL_SIZE_TARGET * UNTRIED_SONG_FRACTION
	
	-- add untried songs
	set list_size to 0
	
	tell application "iTunes"
		
		set input to get every track of user playlist UNTRIED_SONGS
		repeat with aTrack in input
			
			set song_size to size of aTrack
			if list_size + song_size > untried_target_size then
				exit repeat
			end if
			
			-- copy aTrack to the end of songs
			set the end of songs to aTrack
			set list_size to list_size + song_size
			
		end repeat
		
	end tell
	
	return list_size
	
end GetUntriedSongs



-- extract last attempted date from comment of track, returns null if none
on GetLastAttemptedDate(theTrack)
	
	tell application "iTunes"
		
		set com to comment of theTrack
		
		set identLoc to offset of "WSP LAD: " in com -- locate WSP date keywords
		
		if identLoc is equal to 0 then
			return null -- keyword not found, return null
		end if
		
		set startPos to identLoc + 9
		set endPos to identLoc + 28
		set last_attempted_date_string to text startPos thru endPos of com -- extract date from comment
		
	end tell
	
	set last_attempted_date to date (last_attempted_date_string) -- TODO - needs Applescript date creation syntax adjustment
	
	return last_attempted_date
	
end GetLastAttemptedDate




-- convert date into sortable date and time
on DateToSortableString(date)
	
	log date
	-- set sort_string to								-- TODO - needs Applescript date syntax specific code, ideally year / month / day / hour / minute / second so it'll sort but that's optional as is going all the way down to seconds
	
	return sort_string
	
end DateToSortableString



-- get last attempted date and update track rating based on plays & skips
on UpdateTrackInfo(theTrack)
	
	tell application "iTunes"
		
		set play_date to GetDate(played date of theTrack) of me
		set skip_date to GetDate(skipped date of theTrack) of me
		set last_attempted_date to GetLastAttemptedDate(theTrack) of me
		
		-- determine most recent of play or skip date
		set new_attempt_date to play_date
		
		if skip_date > new_attempt_date then
			set new_attempt_date to skip_date
		end if
		
		if last_attempted_date is equal to null then
			
			-- if no rating already, set to default first time guess
			set old_rating to rating of theTrack
			
			if rating of theTrack is equal to 0 then
				
				-- first attempt in the system, use default ratings
				if play_date ³ skip_date then
					set rating of track to PLAYED_FIRST_TIME_RATING
				else
					set rating of track to SKIPPED_FIRST_TIME_RATING
				end if
			end if
			
			-- no stored last attempted date, write new one
			set comment of theTrack to "WSP LAD: " & DateToSortableString(new_attempt_date) of me
			
		else if new_attempt_date > last_attempted_date then
			
			-- new attempt was made
			if play_date > last_attempted_date then
				
				if skip_date < last_attempted_date then
					
					-- play, see if rating should be increased
					set elapsed_time to new_attempt_date - last_attempted_date
					
					-- compute rounded rating
					set new_rating to 101 - elapsed_time / (3600 * 24 * RATING_REPEAT_INTERVAL)
					
					set old_rating to rating of theTrack
					
					if new_rating > old_rating then
						set rating of theTrack to round (old_rating + (new_rating - old_rating) * PLAY_LEARN_RATE)
					end if
					
				end if
				
			else
				
				-- skip, see if rating should be decreased
				set elapsed_time to new_attempt_date - last_attempted_date
				
				-- compute rounded rating
				set new_rating to 101 - elapsed_time / (3600 * 24 * RATING_REPEAT_INTERVAL)
				
				if new_rating < 1 then
					set new_rating to 1
				end if
				
				set old_rating to rating of theTrack
				
				if new_rating < old_rating then
					set rating of theTrack to round (old_rating + (new_rating - old_rating) * SKIP_LEARN_RATE)
				end if
				
			end if
			
			-- write new attemtped date
			set comment of theTrack to "WSP LAD: " & DateToSortableString(new_attempt_date) of me
			
		end if
		
		return new_attempt_date
		
	end tell
	
end UpdateTrackInfo



-- sort songs by decreasing play pressure
on SortByPlayPressure(songs)
	
	-- sort songs
	-- TODO need to sort the songs by play pressure, decreasing		
	
end SortByPlayPressure



-- select the songs with the greatetst play pressure
on GetHighestPressureSongs(chosen_tracks, all_songs, target_size)
	
	-- sort songs by decreasing play pressure
	SortByPlayPressure(all_songs) of me
	
	-- add to selected tracks until target size is reached
	set size to 0
	
	repeat with Song in all_songs
		
		set song_size to size of Song
		if size + song_size > target_size then
			exit repeat
		end if
		
		copy itunes_track of Song to the end of chosen_tracks
		set size to size + song_size
		
	end repeat
	
end GetHighestPressureSongs



-- get songs that have been attempted before, and process songs with new information
on GetTriedSongs(chosen_tracks, target_size)
	
	set songs to {} -- array of song objects (has a play pressure for each)
	
	tell application "iTunes"
		
		set input to get every track of user playlist TRIED_SONGS
		repeat with aTrack in input
			
			-- see if a play attempt has been made since last time script was run or if song is new to the music system
			set last_attempted_date to UpdateTrackInfo(aTrack) of me
			
			-- create song object, which computes play pressure
			set newSong to my createSong(aTrack, last_attempted_date)
			copy newSong to end of songs
			
		end repeat
		
	end tell
	
	-- choose songs with the highest pressure for output
	GetHighestPressureSongs(chosen_tracks, songs, target_size) of me
	
end GetTriedSongs



on GetSongsToAdd()
	
	set songs to {}
	
	-- get untried songs (if any)
	set untried_size to GetUntriedSongs(songs) of me
	
	-- get tried songs to fill up rest of playlist, and process songs with new information
	GetTriedSongs(songs, TOTAL_SIZE_TARGET - untried_size) of me
	
	return songs
	
end GetSongsToAdd








tell application "iTunes"
	
	set currDate to (current date) -- get current date
	
	set old_i to fixed indexing -- enable fixed indexing
	set fixed indexing to true
	
	-- get songs to be added to output playlist, updating attempted and new ones in the process
	set output_songs to GetSongsToAdd() of me
	
	-- write songs to output playlist
	WriteSongs(output_songs) of me
	
	set fixed indexing to old_i
	
end tell















