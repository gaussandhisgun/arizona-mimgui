#!/bin/bash
rm *.png
for i in $(seq 1 9790); do
	wget "https://reserve-cdn.azresources.cloud/projects/arizona-rp/assets/images/donate/${i}.png" -O "${i}.png"	
done
echo "Finished"
