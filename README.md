# raspberrybackups
I use this script daily to back up my Windows SMB share to two DAS drives connected to my Raspberry Pi 5.

- Runs a health check on both attached drives
- Creates an image of the Raspberry Pi system and uploads it to my Windows share drive, then shrinks that image. Retains 7 days of image history.
- rsync backs up the Windows share to the primary hard drive
- rsync mirrors the entire primary drive to the secondary drive
- Everything is logged and a summary is emailed

Sometimes I will do a simple drag-and-drop to the Primary hard drive for files I want backed up. This is why the second rsync mirrors the entire primary hard drive. The primary backup hard drive has my Windows share, and various other files I've hand-selected.

I've done a ton of troubleshooting with rsync to reduce the backup time. You'll see a lot of folder exclusions in the rsync command. This is because Windows has annoying symbolic links that pop up in SMB sharing, and it causes recursion loops with rsync. You have to exclude these symbolic links, or rsync will fail.
