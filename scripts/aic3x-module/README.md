# AIC3x driver sources for the A733 vendor kernel

The TLV320AIC3104 on the HAT is an AIC3x-family part, so it needs
`snd-soc-tlv320aic3x`, not `snd-soc-tlv320aic31xx` (the AIC3100/3110 family,
whose Page 0 register map differs). The vendor kernel does not build it
(`# CONFIG_SND_SOC_TLV320AIC3X is not set`), so it is built out-of-tree here.

These three files are the driver from the vendor kernel tree
(`sound/soc/codecs/tlv320aic3x.{c,h}` and `tlv320aic3x-i2c.c`) as of kernel
`6.6.98-vendor-sun60iw2`. They are GPL-2.0, like the kernel.

Do not substitute the copy in the upstream firmware repository
(`firmware/deploy/audio/aic3x-dkms/`): that `.c`/`.h` pair is inconsistent and
fails to compile with `AIC3X_MICBIAS_AVDDV undeclared`.

## Build on the board

Kernel headers have to be installed on the board
(`/lib/modules/$(uname -r)/build` must exist). The driver includes
`<sound/tlv320aic3x.h>`, which is not in that headers tree, so install the
header first.

```bash
cd scripts/aic3x-module
install -D -m 644 tlv320aic3x.h /usr/src/linux-headers-$(uname -r)/include/sound/tlv320aic3x.h
printf 'obj-m := snd-aic3x.o\nsnd-aic3x-y := tlv320aic3x.o tlv320aic3x-i2c.o\n' > Makefile
make -C /lib/modules/$(uname -r)/build M=$PWD modules
install -D -m 644 snd-aic3x.ko /lib/modules/$(uname -r)/extra/snd-aic3x.ko
depmod -a
```

Check the vermagic before rebooting: it has to read
`6.6.98-vendor-sun60iw2 SMP preempt mod_unload aarch64`. A module built against
the plain `6.6.98` release string is refused on load.

```bash
modinfo /lib/modules/$(uname -r)/extra/snd-aic3x.ko | grep vermagic
```

The module loads when the overlay registers the codec; `lsmod | grep aic3x`
and `ls /sys/bus/i2c/drivers/tlv320aic3x/` should then show `0-0018`.
