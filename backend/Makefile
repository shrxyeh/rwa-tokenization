.PHONY: build test test-v coverage deploy-local deploy-sepolia fmt lint clean

# ── Build ──────────────────────────────────────────────────────────────────────

build:
	forge build

# ── Tests ─────────────────────────────────────────────────────────────────────

test:
	forge test

test-v:
	forge test -vvv

coverage:
	forge coverage --report lcov
	genhtml lcov.info -o coverage/

# ── Local dev ──────────────────────────────────────────────────────────────────

anvil:
	anvil --fork-url $(SEPOLIA_RPC_URL)

deploy-local:
	forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

demo-local:
	forge script script/Demo.s.sol --rpc-url http://localhost:8545 --broadcast

# ── Sepolia ───────────────────────────────────────────────────────────────────

deploy-sepolia:
	source .env && forge script script/Deploy.s.sol \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast \
		--verify \
		--etherscan-api-key $$ETHERSCAN_API_KEY

grant-role:
	source .env && forge script script/GrantRole.s.sol \
		--rpc-url $$SEPOLIA_RPC_URL \
		--broadcast

# ── Code quality ──────────────────────────────────────────────────────────────

fmt:
	forge fmt

lint:
	forge fmt --check

# ── Cleanup ───────────────────────────────────────────────────────────────────

clean:
	forge clean
	rm -rf lcov.info coverage/
