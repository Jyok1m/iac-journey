VAULT_FILES := $(wildcard ansible/vaults/*) $(wildcard ansible/*/*/vault.yml)
IS_ENCRYPTED = head -n1 "$$f" | grep -q '^\$$ANSIBLE_VAULT'

.DEFAULT_GOAL := help
.PHONY: help encrypt decrypt

help:
	@echo "encrypt  chiffre les vaults non chiffrés"
	@echo "decrypt  déchiffre les vaults chiffrés"

# ------------------------------------------------------------------ #
#                            Ansible Vault                           #
# ------------------------------------------------------------------ #

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
