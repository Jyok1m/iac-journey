VAULT_FILES := $(wildcard ansible/vaults/*) $(wildcard ansible/*/*/vault.yml)
IS_ENCRYPTED = head -n1 "$$f" | grep -q '^\$$ANSIBLE_VAULT'

.DEFAULT_GOAL := help
.PHONY: help encrypt decrypt mail mail-check

help:
	@echo "encrypt     chiffre les vaults non chiffrés"
	@echo "decrypt     déchiffre les vaults chiffrés"
	@echo "mail        déploie le serveur mail de bout en bout (DNS compris)"
	@echo "mail-check  dry-run du rôle mailcow"

# D'une machine nue à un serveur mail vérifié. Terraform est piloté par le rôle,
# rien à lancer à la main. TAGS=... pour ne rejouer qu'une étape.

TAGS ?= mail

mail:
	ansible-playbook ansible/site.yml --tags "$(TAGS)"

mail-check:
	ansible-playbook ansible/site.yml --tags "$(TAGS)" --check --diff

encrypt:
	@for f in $(VAULT_FILES); do \
		[ -f "$$f" ] || continue; \
		if $(IS_ENCRYPTED); then \
			echo "skip (déjà chiffré) : $$f"; \
		else \
			echo "encrypt : $$f"; ansible-vault encrypt "$$f"; \
		fi; \
	done

decrypt:
	@for f in $(VAULT_FILES); do \
		[ -f "$$f" ] || continue; \
		if $(IS_ENCRYPTED); then \
			echo "decrypt : $$f"; ansible-vault decrypt "$$f"; \
		else \
			echo "skip (déjà déchiffré) : $$f"; \
		fi; \
	done
