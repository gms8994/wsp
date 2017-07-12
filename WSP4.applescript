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
property UNTRIED_SONG_FRACTION : 0.3 -- fraction of output to set to untried songs (if not enough tried ones, this could be larger)
property RATING_REPEAT_INTERVAL : 7 -- repeat interval, in days, per rating tick (r = 100: 1 * interval, r = 99: 2 * interval, etc.   r = 1: 100 * interval, note r = 0 means unrated )
property SKIP_LEARN_RATE : 0.9 -- when skipped, new rating is set to old_rating + (new_rating-old_rating) * skip_learn_rate
property PLAY_LEARN_RATE : 0.3 -- when played, new rating is set to old_rating + (new_rating-old_rating) * play_learn_rate
property PLAYED_FIRST_TIME_RATING : 100 -- since there's no time period the first time a song is attempted, what rating do I use if it's played?
property SKIPPED_FIRST_TIME_RATING : 90 -- since there's no time period the first time a song is attempted, what rating do I use if it's skipped?

-- advanced control parameters; not much reason to adjust these
property TRIED_SONGS : "WSP4 Tried" -- Change to "WSP4 Tried" after debugging				-- playlist of songs with previous attempts (play & skip dates give us soemthing to work with)
property UNTRIED_SONGS : "WSP4 Untried" -- songs that have never been attempted (no play & skip dates)
property MISSING_VALUE_DATE : "1900-01-01 00:00:00"

property TOTAL_SIZE_TARGET : OUTPUT_SIZE * 1024 * 1024
property SONGS_TO_ADD : {}
property PRESSURIZED_SONGS : {}
property CURRENT_DATE : (current date) -- get current date




-- create date from iTunes value, checking if it is invalid and, if so, returning one far in the past instead to simplify comparisons
on GetDate(itunes_date)
	if (itunes_date as string) is equal to "missing value" then
		return my convertDate(MISSING_VALUE_DATE)
	else
		return itunes_date
	end if
end GetDate

-- Convert date function. Call with string in YYYY-MM-DD HH:MM:SS format (time part optional)
to convertDate(textDate)
	set resultDate to the current date
	
	set the year of resultDate to (text 1 thru 4 of textDate)
	set the month of resultDate to (text 6 thru 7 of textDate)
	set the day of resultDate to (text 9 thru 10 of textDate)
	set the time of resultDate to 0
	
	if (length of textDate) > 10 then
		set the hours of resultDate to (text 12 thru 13 of textDate)
		set the minutes of resultDate to (text 15 thru 16 of textDate)
		
		if (length of textDate) > 16 then
			set the seconds of resultDate to (text 18 thru 19 of textDate)
		end if
	end if
	
	return resultDate
end convertDate

-- song class, copntains play pressure information for tracks
on createSong(theTrack, last_attempted_date)
	script Song
		property itunes_track : null -- iTunes song
		property theSize : null -- size of song
		property theRating : null -- rating of song
		property play_pressure : null -- pressure for being played
		
		on getItunesTrack()
			return itunes_track
		end getItunesTrack
		
		on getName()
			return name of itunes_track
		end getName
		
		on getPressure()
			return play_pressure
		end getPressure
		
		on getSize()
			return theSize
		end getSize
		
		on calculatePressure(theTrack, last_attempted_date)
			
			set itunes_track to theTrack
			
			using terms from application "iTunes"
				
				set theSize to size of theTrack
				set theRating to rating of theTrack
				
			end using terms from
			
			set elapsed_time to CURRENT_DATE - last_attempted_date
			set multiplier to RATING_REPEAT_INTERVAL * (101 - theRating)
			set play_pressure to elapsed_time / multiplier
			
		end calculatePressure
		
	end script
	
	-- constructor
	tell Song
		
		calculatePressure(theTrack, last_attempted_date)
		
	end tell
	
	return Song
	
end createSong

-- write songs to output playlist
on WriteSongs()
	
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
		repeat with aTrack in SONGS_TO_ADD
			if name of aTrack as string is not "missing value" then
				duplicate aTrack to playlist OUTPUT_PLAYLIST_NAME
			end if
		end repeat
		
	end tell
	
end WriteSongs


-- get songs that have never been attempted before
on GetUntriedSongs()
	-- compute amount of untried songs to add
	set untried_target_size to TOTAL_SIZE_TARGET * UNTRIED_SONG_FRACTION
	
	-- add untried songs
	set list_size to 0
	
	tell application "iTunes"
		
		set input to get every track of user playlist UNTRIED_SONGS
		repeat with aTrack in input
			
			set song_size to size of aTrack
			if (song_size as string) is equal to "missing value" then
				set song_size to 0
			end if
			
			if list_size + song_size > untried_target_size then
				exit repeat
			end if
			
			set the end of SONGS_TO_ADD to aTrack
			-- copy aTrack to the end of SONGS_TO_ADD
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
		set endPos to count (com)
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
					set rating of theTrack to PLAYED_FIRST_TIME_RATING
				else
					set rating of theTrack to SKIPPED_FIRST_TIME_RATING
				end if
			end if
			
			-- no stored last attempted date, write new one
			set comment of theTrack to "WSP LAD: " & new_attempt_date
			
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
			set comment of theTrack to "WSP LAD: " & new_attempt_date
			
		end if
		
		return new_attempt_date
		
	end tell
	
end UpdateTrackInfo

-- http://macscripter.net/viewtopic.php?pid=59460#p59460
on pressure_sort(array, leftEnd, rightEnd) -- Hoare's QuickSort Algorithm
	script A
		property L : array
	end script
	set {i, j} to {leftEnd, rightEnd}
	set v to item ((leftEnd + rightEnd) div 2)'s getPressure() of A's L -- pivot in the middle
	repeat while (j > i)
		repeat while ((item i of A's L)'s getPressure() < v)
			set i to i + 1
		end repeat
		repeat while ((item j of A's L)'s getPressure() > v)
			set j to j - 1
		end repeat
		if (not i > j) then
			tell A's L to set {item i, item j} to {item j, item i} -- swap
			set {i, j} to {i + 1, j - 1}
		end if
	end repeat
	if (leftEnd < j) then pressure_sort(A's L, leftEnd, j)
	if (rightEnd > i) then pressure_sort(A's L, i, rightEnd)
end pressure_sort

-- sort songs by decreasing play pressure
on SortByPlayPressure()
	pressure_sort(PRESSURIZED_SONGS, 1, count of PRESSURIZED_SONGS)
	set PRESSURIZED_SONGS to reverse of PRESSURIZED_SONGS
end SortByPlayPressure

-- select the songs with the greatetst play pressure
on GetHighestPressureSongs(target_size)
	
	-- sort songs by decreasing play pressure
	SortByPlayPressure() of me
	
	-- add to selected tracks until target size is reached
	set theSize to 0
	
	repeat with Song in PRESSURIZED_SONGS
		
		set song_size to Song's getSize()
		if (song_size as string) is equal to "missing value" then
			set song_size to 0
		end if
		
		if theSize + song_size > target_size then
			exit repeat
		end if
		
		set the end of SONGS_TO_ADD to Song's getItunesTrack()
		set theSize to theSize + song_size
		
	end repeat
	
end GetHighestPressureSongs



-- get songs that have been attempted before, and process songs with new information
on GetTriedSongs(target_size)
	
	tell application "iTunes"
		
		set input to get every track of user playlist TRIED_SONGS
		repeat with aTrack in input
			
			-- see if a play attempt has been made since last time script was run or if song is new to the music system
			set last_attempted_date to UpdateTrackInfo(aTrack) of me
			
			-- create song object, which computes play pressure
			set newSong to my createSong(aTrack, last_attempted_date)
			
			set end of PRESSURIZED_SONGS to newSong
			
		end repeat
		
	end tell
	
	-- choose songs with the highest pressure for output
	GetHighestPressureSongs(target_size) of me
	
end GetTriedSongs



on GetSongsToAdd()
	
	set untried_size to 0
	-- get untried songs (if any)
	set untried_size to GetUntriedSongs() of me
	
	-- get tried songs to fill up rest of playlist, and process songs with new information
	GetTriedSongs(TOTAL_SIZE_TARGET - untried_size) of me
	
end GetSongsToAdd








tell application "iTunes"
	
	set old_i to fixed indexing -- enable fixed indexing
	set fixed indexing to true
	
	-- get songs to be added to output playlist, updating attempted and new ones in the process
	GetSongsToAdd() of me
	
	-- write songs to output playlist
	WriteSongs() of me
	
	set fixed indexing to old_i
	
end tell















