.PHONY: setup check start stop test logs lint lint-fix unit

setup:
	bash scripts/setup.sh

check:
	bash scripts/check.sh

start:
	bash start.sh

stop:
	bash stop.sh

test:
	bash scripts/test.sh

logs:
	bash scripts/logs.sh

lint:
	cd backend && npm run lint

lint-fix:
	cd backend && npm run lint:fix

unit:
	cd backend && npm test