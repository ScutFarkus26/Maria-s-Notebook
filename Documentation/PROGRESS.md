# Progress: two-zone move to CloudKit Production

Repo copy of the build board (https://claude.ai/artifact/VZpfwHWT7cGz1vkn3xNzNm). Plan: Part 2 of the two-zone Production move.

## Milestones
- [x] 1. Two-zone app changes
- [x] 2. Production schema
- [x] 3. Mac on Production
- [x] 4. Assistant test
- [x] 5. iPhone + iPad
- [ ] 6. Tidy up (active)

## 5. iPhone + iPad (done 2026-09-28)

### Build
- [x] Release build of main for Production (ab5b2200)

### Install
- [x] Mac on the same build
- [x] iPhone 18 Pro installed
- [x] iPad mini installed

### First download
- [x] iPhone shows the whole notebook (38 students, 3,107 attendance)
- [x] iPad shows the whole notebook (same counts)

### Sync checks
- [x] A change on one device reaches the other
- [ ] Attendance roll redraws when another device marks (fix 978fb33d; ships with attendance parity)
- [x] Production holds exactly two zones
- [x] Push main to GitHub

## 6. Tidy up

### Tidy up
- [ ] Move store copies with children's data to the Trash
- [ ] Update memory and docs for the Production move

### After step 6
- [ ] Ship attendance parity + roll redraw fix together
- [ ] Make former students easier to find on iPhone/iPad (optional)
