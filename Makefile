VERSION ?= 0.6

BINS += bin/sbsign.safeboot
BINS += bin/sign-efi-sig-list.safeboot
BINS += bin/tpm2-totp
BINS += bin/tpm2

all: $(BINS) update-certs

#
# sbsign needs to be built from a patched version to avoid a
# segfault when using the PKCS11 engine to talk to the Yubikey.
#
SUBMODULES += sbsigntools
bin/sbsign.safeboot: sbsigntools/Makefile
	$(MAKE) -C $(dir $<)
	mkdir -p $(dir $@)
	cp $(dir $<)src/sbsign $@
sbsigntools/Makefile: sbsigntools/autogen.sh
	cd $(dir $@) ; ./autogen.sh && ./configure
sbsigntools/autogen.sh:
	git submodule update --init --recursive --recommend-shallow sbsigntools

#
# sign-efi-sig-list needs to be built from source to have support for
# the PKCS11 engine to talk to the Yubikey.
#
SUBMODULES += efitools
bin/sign-efi-sig-list.safeboot: efitools/Makefile
	$(MAKE) -C $(dir $<) sign-efi-sig-list
	mkdir -p $(dir $@)
	cp $(dir $<)sign-efi-sig-list $@
efitools/Makefile:
	git submodule update --init efitools

#
# tpm2-tss is the library used by tpm2-tools
#
SUBMODULES += tpm2-tss

libtss2-esys = tpm2-tss/src/tss2-esys/.libs/libtss2-esys.a
$(libtss2-esys): tpm2-tss/Makefile
	$(MAKE) -C $(dir $<)
	mkdir -p $(dir $@)
tpm2-tss/Makefile:
	git submodule update --init $(dir $@)
	cd $(dir $@) ; ./bootstrap && ./configure \
		--disable-doxygen-doc \

#
# tpm2-tools is the branch with bundling and ecc support built in
#
SUBMODULES += tpm2-tools

tpm2-tools/bundle/tpm2: tpm2-tools/Makefile 
	$(MAKE) -C $(dir $<)
	cd $(dir $@) ; bash -x ./bundle

bin/tpm2: tpm2-tools/bundle/tpm2
	cp $< $@

tpm2-tools/Makefile: $(libtss2-esys)
	git submodule update --init $(dir $@)
	cd $(dir $@) ; ./bootstrap
	cd $(dir $@) ; ./configure \
		TSS2_ESYS_3_0_CFLAGS=-I../tpm2-tss/include \
		TSS2_ESYS_3_0_LIBS="../$(libtss2-esys) -ldl" \



#
# tpm2-totp is build from a branch with hostname support
#
SUBMODULES += tpm2-totp
bin/tpm2-totp: tpm2-totp/Makefile
	$(MAKE) -C $(dir $<)
	mkdir -p $(dir $@)
	cp $(dir $<)/tpm2-totp $@
tpm2-totp/Makefile:
	git submodule update --init tpm2-totp
	cd $(dir $@) ; ./bootstrap && ./configure


#
# Extra package building requirements
#
requirements:
	DEBIAN_FRONTEND=noninteractive \
	apt install -y \
		devscripts \
		debhelper \
		libqrencode-dev \
		libtss2-dev \
		efitools \
		gnu-efi \
		opensc \
		yubico-piv-tool \
		libengine-pkcs11-openssl \
		build-essential \
		binutils-dev \
		git \
		pkg-config \
		automake \
		autoconf \
		autoconf-archive \
		initramfs-tools \
		help2man \
		libssl-dev \
		uuid-dev \
		shellcheck \
		curl \
		libjson-c-dev \
		libcurl4-openssl-dev \


# Remove the temporary files
clean:
	rm -rf bin $(SUBMODULES)
	mkdir $(SUBMODULES)
	git submodule update --init --recursive --recommend-shallow 

# Regenerate the source file
tar: clean
	tar zcvf ../safeboot_$(VERSION).orig.tar.gz \
		--exclude .git \
		--exclude debian \
		.

package: tar
	debuild -uc -us
	cp ../safeboot_$(VERSION)_amd64.deb safeboot-unstable.deb


# Run shellcheck on the scripts
shellcheck:
	for file in \
		sbin/safeboot* \
		sbin/tpm2-attest \
		initramfs/*/* \
	; do \
		shellcheck $$file ; \
	done

# Fetch several of the TPM certs and make them usable
# by the openssl verify tool.
# CAB file from Microsoft has all the TPM certs in DER
# format.  openssl x509 -inform DER -in file.crt -out file.pem
# https://docs.microsoft.com/en-us/windows-server/security/guarded-fabric-shielded-vm/guarded-fabric-install-trusted-tpm-root-certificates
# However, the STM certs in the cab are corrupted? so fetch them
# separately
update-certs:
	#./refresh-certs
	c_rehash certs
