.PHONY: test run-bserve

test:
	python3 -m unittest discover -s tests -v

run-bserve:
	python3 src/server/bserve.py ./www 9000
