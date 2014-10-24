#!/bin/bash

function symlink {
	[[ ! $1 ]] && help symlink
	local castle=$1
	castle_exists "$castle"
	local repo="$repos/$castle"
	if [[ ! -d $repo/home ]]; then
		ignore 'ignored' "$castle"
		return $EX_SUCCESS
	fi
	for filename in $(get_repo_files "$repo"); do
		remote="$repo/home/$filename"
		local="$HOME/$filename"

		if [[ -e $local || -L $local ]]; then
			# $local exists (but may be a dead symlink)
			if [[ -L $local && $(readlink "$local") == "$remote" ]]; then
				# $local symlinks to $remote.
				if [[ -d $remote && ! -L $remote ]]; then
					# If $remote is a directory -> legacy handling.
					rm "$local"
				else
					# $local points at $remote and $remote is not a directory
					if $VERBOSE; then
						ignore 'identical' "$filename"
					fi
					continue
				fi
			else
				# $local does not symlink to $remote
				if [[ -d $local && -d $remote && ! -L $remote ]]; then
					# $remote is a real directory while
					# $local is a directory or a symlinked directory
					# we do not take any action regardless of which it is.
					if $VERBOSE; then
						ignore 'identical' "$filename"
					fi
					continue
				fi
				if $SKIP; then
					ignore 'exists' "$filename"
					continue
				fi
				if ! $FORCE; then
					prompt_no 'conflict' "$filename exists" "overwrite?" || continue
				fi
				# Delete $local. If $remote is a real directory,
				# $local must be a file (because of all the previous checks)
				rm -rf "$local"
			fi
		fi

		if [[ ! -d $remote || -L $remote ]]; then
			# $remote is not a real directory so we create a symlink to it
			pending 'symlink' "$filename"
			ln -s "$remote" "$local"
		else
			pending 'directory' "$filename"
			mkdir "$local"
		fi

		success
	done
	return $EX_SUCCESS
}

# Fetches all files and folders in a repository that are tracked by git
# Works recursively on submodules as well
function get_repo_files {
	# Resolve symbolic links
	# e.g. on osx $TMPDIR is in /var/folders...
	# which is actually /private/var/folders...
	# We do this so that the root part of $toplevel can be replaced
	# git resolves symbolic links before it outputs $toplevel
	local root=$(cd "$1"; pwd -P)
	# This function is passed to git submodule foreach
	list_fn="
	# toplevel/path relative to root
	local repo=\${toplevel/#${root//\//\\/}/}/\$path
	# If we are at root, remove the slash in front
	repo=\${repo/#\//}
	# We are only interested in submodules under home/
	if [[ \$repo =~ ^home ]]; then
		cd \"\$toplevel/\$path\"
		# List the files and prefix every line
		# with the relative repo path
		git ls-files | sed \"s#^#\${repo//#/\\#}/#\"
	fi"
	(
		local path
		while read path; do
			# Remove quotes from ls-files
			# (used when there are newlines in the path)
			path=${path/#\"/}
			path=${path/%\"/}
			# Check if home/ is a submodule
			[[ $path == 'home' ]] && continue
			# Remove the home/ part
			path=${path/#home\//}
			# Print the file path
			printf "%s\n" "$path"
			# Get the path of all the parent directories up to the repo root.
			while true; do
				path=$(dirname "$path")
				# If path is '.' we're done
				[[ $path == '.' ]] && break
				# Print the path
				printf "%s\n" "$path"
			done
		# Enter the repo, list the repo root files in home and do the same for any submodules
		done < <(cd "$root" && git ls-files 'home/' && git submodule --quiet foreach --recursive "$list_fn")
	) | sort -u # sort the results and make the list unique
}
