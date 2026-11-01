#!/bin/sh
# aic3104 HAT mixer defaults.
#  - PGA Capture Switch is muted by default and the left ADC stays unpowered
#    unless the Mic2L route is enabled, so both have to be set explicitly.
#  - Right PGA Mixer Line1L must stay on: with it off the codec's capture path
#    collapses and the recorded stream becomes digital garbage.
#  - Both external mics are mixed into both channels (dual-mic mono).
#  - The DAC -> line mixer gains power up at 6, which is -56 dB on a 0.5 dB
#    scale (max 118). Playback is practically inaudible until they are raised.
#  - The analog PGA bypass paths are muted so the mixer only carries the DAC.
CARD=aic3104hat
i=0
while [ $i -lt 50 ]; do
    amixer -c "$CARD" cget name='PGA Capture Switch' >/dev/null 2>&1 && break
    i=$((i + 1))
    sleep 0.2
done

amixer -c "$CARD" cset name='PGA Capture Switch' on,on
amixer -c "$CARD" cset name='PGA Capture Volume' 40

amixer -c "$CARD" cset name='Left PGA Mixer Line1L Switch' on
amixer -c "$CARD" cset name='Left PGA Mixer Line1R Switch' on
amixer -c "$CARD" cset name='Left PGA Mixer Mic2L Switch' on
amixer -c "$CARD" cset name='Left PGA Mixer Mic2R Switch' off

amixer -c "$CARD" cset name='Right PGA Mixer Line1L Switch' on
amixer -c "$CARD" cset name='Right PGA Mixer Line1R Switch' on
amixer -c "$CARD" cset name='Right PGA Mixer Mic2L Switch' on
amixer -c "$CARD" cset name='Right PGA Mixer Mic2R Switch' off

# Playback: 0 dB from the DAC into the line mixer and out of LINE OUT.
for c in 'Left Line Mixer DACL1' 'Left Line Mixer DACR1' \
         'Right Line Mixer DACL1' 'Right Line Mixer DACR1' \
         'Line DAC' 'HP DAC' 'HPCOM DAC'; do
    amixer -c "$CARD" sset "$c" 100% >/dev/null 2>&1
    amixer -c "$CARD" sset "$c" on >/dev/null 2>&1
done

# Keep the unused analog bypass paths out of the mix.
for c in 'Left Line Mixer PGAL Bypass' 'Left Line Mixer PGAR Bypass' \
         'Right Line Mixer PGAL Bypass' 'Right Line Mixer PGAR Bypass' \
         'Line PGA Bypass' 'HP PGA Bypass' 'HPCOM PGA Bypass'; do
    amixer -c "$CARD" sset "$c" off >/dev/null 2>&1
done

amixer -c "$CARD" sset 'Line' 9 >/dev/null 2>&1 || true
amixer -c "$CARD" sset 'Line' on >/dev/null 2>&1 || true

# Keep playback quiet: the amplifier is loud and the speaker sits close by.
amixer -c "$CARD" sset PCM 60 >/dev/null 2>&1 || true
exit 0
