.PHONY: build test doc dist clean

## build — compile a static binary via ros dump executable
build:
	ros dump executable chat-dapla-deploy --output chat-dapla-deploy

## test — run the e2e suite against a live deployment
test:
	./chat-dapla-deploy.ros e2e

## doc — generate HTML documentation via docs.ros
doc:
	ros docs.ros

## dist — package the binary for distribution
dist: build
	tar czf chat-dapla-deploy.tar.gz chat-dapla-deploy

## clean — remove build artifacts
clean:
	rm -f chat-dapla-deploy chat-dapla-deploy.tar.gz
