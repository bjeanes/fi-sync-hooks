# Github:FI Sync

This project is a set of git hooks that facilitates bi-directional syncing between a Github:FI installation and another remote (e.g. Gitosis).

It was born out of the need to trial Github:FI at Groupon using a single team, without transitioning all developers and infrastructure over to it.

These hooks could probably be adapted fairly simply to sync between any other two (or more) repositories...

# How does it work?

Basically, I use a Redis as a binary semaphore / mutex so that only one of the two remotes can be pushed to at any given time. A `pre-receive` git hook locks the repository using a common key. Later, a `post-receive` hook is fired which will mirror the changes to the other repository, then remove the lock.

# Warning

`git push --mirror`, which is the core of these hooks, is inherently destructive (it is similar to doing `git push --all --force` as well as performing remote branch deletions. Neither I nor Groupon accept any liability for issues arising due to the use of these scripts. Test this syncing thorougly with a throw-away repository before rolling this out into production.

I've done my best to detect sync failures and prevent further syncing (which could cause data loss) by locking both repos (which requires manual intervention). In my experience, the hooks have been very reliable barring any network issues between the two servers.

If you do get into trouble, remember that thanks to git being distributed, you can usually undo any damage by simply pushing lost changes again once you've manually unlocked the Redis semaphore.

Unlocking the semaphore should be done after you've pulled down changes from both remotes locally to make sure you have the most up-to-date merged version to re-push. To do it, simply SSH into the Redis server (Github:FI by default) and run something like `redis-cli keys 'sync/<repo-name>/*' | xargs redis-cli del`.

# Caveats/Limitations

Due to a limitation of git, if somebody hits `^C` when they are pushing, it can sometimes cause the `post-receive` hook to fail which means syncing and releasing the lock fails. This will mean manual sync and fix up is required. I do not yet have a work around.

# How to use it

First, modify `repo_sync.rb` and fill out your server details at the top of the file. Also, fill in the repos you want to sync in the `REPOS` constant.

Next, you need to install the hooks into the various servers.

## Github:FI

Github:FI already has a folder for global git hooks, so there is no need to go poking around the internals of each repository (since they already have hooks there anyway).

Simply clone this repo (or your fork of it) into `/opt/github/hooks/sync`.

Then, run `ln -s /opt/github/hooks/sync/pre-receive /opt/github/hooks/pre-receive/00-lock-repo` and `ln -s /opt/github/hooks/sync/post-receive /opt/github/hooks/post-receive/99-unlock-repo`

## Gitosis (or most other servers, probably)

With Gitosis, you need to install the hooks into each repository separately.

To maintain some consistency between Gitosis and Github:FI, run `mkdir
-p ~git/hooks` and then clone this repo into `~git/hooks/sync`

Assuming that none of the repos have existing custom hooks, you may be able to get away with doing something like:

    cd /home/git/repositories
    repos="`ls -1`"

    for repo in $repos; do
      mv $repo/hooks{,.old}
      ln -s ~git/hooks/sync $repo/hooks
    done

You can place the `repos=...` line with some other list for finer control.

# License (MIT)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
