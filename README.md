# raspberrybackups
I use this script daily to back up my Windows SMB share to two DAS drives connected to my Raspberry Pi 5.

- Runs a health check on both attached drives
- Creates an image of the Raspberry Pi system and uploads it to my Windows share drive, then shrinks that image. Retains 7 days of image history.
- rsync backs up the Windows share to the primary hard drive
- rsync mirrors the entire primary drive to the secondary drive
- Everything is logged and a summary is emailed

Sometimes I will do a simple drag-and-drop to the Primary hard drive for files I want backed up. This is why the second rsync mirrors the entire primary hard drive. The primary backup hard drive has my Windows share, and various other files I've hand-selected.
