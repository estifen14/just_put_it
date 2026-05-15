# Automated Testing Instructions

Welcome to the `just_put_it` project! Our backend utilizes **Testcontainers** to dynamically spin up isolated, ephemeral PostgreSQL databases during our test suite executions. This ensures our integration tests have strict parity with our production environment without relying on shared or locally installed databases.

To run the automated acceptance tests, use the Maven wrapper:

```bash
cd ~/Projects/just_put_it/services/notes_service
./mvnw clean test
```

---

## ⚠️ Known Issue: Docker Desktop v4.30.0+ 

If you are a new developer onboarding to the project and you encounter a **`ContainerFetchException`** or **`BadRequestException (Status 400)`** when running the tests, please read below.

### The Problem
Docker Desktop version 4.30.0 and newer has started strictly validating the Docker Engine API version and actively rejects requests from API versions older than `1.44`.

Because Testcontainers relies on the `docker-java` client library (which may default to an older API version like `1.32` if not explicitly told otherwise), Docker Desktop forcefully drops the connection, causing your local tests to crash with a `400 Bad Request` during the database provisioning phase.

### The Solution (Local Fix)
The easiest, permanent fix for your local machine is to explicitly instruct the `docker-java` client to use a modern API version. 

You can accomplish this by creating a properties file in your home directory. Run the following command in your terminal:

```bash
echo "api.version=1.44" > ~/.docker-java.properties
```

This ensures that any test suite on your machine using Testcontainers will successfully handshake with Docker Desktop.

### Alternative Solution
If you prefer not to create a global properties file in your home directory, you can also solve this by injecting an environment variable directly into your shell profile (`~/.zshrc` or `~/.bashrc`), or preceding your test commands with it:

```bash
export DOCKER_API_VERSION=1.44
# Then run the tests
./mvnw clean test
```
