# CircleCI & GitHub Container Registry (GHCR) Setup Guide

This guide provides step-by-step instructions for setting up an automated CI/CD pipeline using CircleCI to build a Docker image and push it to the GitHub Container Registry (GHCR).

## Step 1: Generate a GitHub Personal Access Token (PAT)
To allow CircleCI to push Docker images to your GitHub repository's container registry, you must provide it with a secure token.

1. Log in to GitHub.
2. Navigate to **Settings** (click your profile picture in the top right).
3. Scroll down the left sidebar and click **Developer settings**.
4. Click **Personal access tokens** -> **Tokens (classic)**.
5. Click the **Generate new token (classic)** button.
6. In the **Note** field, name it something clear, like `CircleCI GHCR Push Token`.
7. Under **Select scopes**, check the box for **`write:packages`** (this will automatically check `read:packages` as well).
8. Click **Generate token** at the bottom of the page.
9. **IMPORTANT:** Copy the generated token immediately and save it somewhere safe. You will not be able to see it again once you leave the page.

## Step 2: Set Up the Project in CircleCI
1. Log in to [CircleCI](https://circleci.com/) using your GitHub account.
2. On the left sidebar, click **Projects**.
3. Find the `just_put_it` repository in the list and click **Set Up Project**.
4. When prompted about the configuration file, select the option indicating you will provide your own `.circleci/config.yml` file on the `main` branch.

## Step 3: Configure CircleCI Environment Variables
You need to pass your GitHub username and the token you just created into the CircleCI pipeline securely.

1. In the CircleCI dashboard, ensure you are on the `just_put_it` project page.
2. Click the **Project Settings** button (usually a gear icon in the top right).
3. On the left sidebar, click **Environment Variables**.
4. Click **Add Environment Variable** and add the following two variables:
   *   **Name:** `GHCR_USERNAME`
   *   **Value:** Your exact GitHub Username (e.g., `EstifenAbrea`)
   *   **Name:** `GHCR_PAT`
   *   **Value:** The Personal Access Token you copied in Step 1.

---

## Important Concept: Variable Scoping in CircleCI

When writing a CircleCI `config.yml` file, it is critical to understand how shell variables work. 

**The Problem:**
In a CircleCI job, every `- run:` step executes in its own completely isolated shell instance. If you declare a variable in one step:
```yaml
- run:
    name: Step 1
    command: |
      MY_VAR="hello"
```
It will **NOT** exist in the next step:
```yaml
- run:
    name: Step 2
    command: |
      echo $MY_VAR # This will output nothing (an empty string)!
```
Because of this isolation, if you define a calculated variable (like converting a username to lowercase), you typically have to **duplicate the variable definition** in every single `- run:` step that needs it. If you forget to duplicate it, the variable evaluates to an empty string, which often causes commands like `docker push` to fail.

**The Solution (`$BASH_ENV`):**
To share a dynamically calculated variable across all subsequent `- run:` steps without duplicating code, you must export the variable and append it to a special CircleCI file called `$BASH_ENV`. CircleCI automatically loads (sources) this file at the start of every step.

**Example of the Global Variable Trick:**
```yaml
- run:
    name: Setup Global Variables
    command: |
      # Write the export command into the BASH_ENV file
      echo "export SHARED_VAR="My Global Value"" >> $BASH_ENV
- run:
    name: Use the Variable
    command: |
      # The variable is automatically available here and in all future steps!
      echo $SHARED_VAR 
```

---

## Step 4: The Pipeline Configuration File
Create a file at `.circleci/config.yml` in your repository. This optimized pipeline uses the `$BASH_ENV` trick to safely convert the GitHub username to lowercase (a strict requirement for Docker image names) and shares it globally across the build and push steps.

```yaml
version: 2.1

jobs:
  build-and-push:
    docker:
      - image: cimg/base:current
    steps:
      - checkout
      - setup_remote_docker:
          version: docker24
      
      - run:
          name: Setup Global Environment Variables
          command: |
            # 1. Docker requires repository names to be strictly lowercase.
            # 2. We use 'tr' to convert GHCR_USERNAME to lowercase.
            # 3. We save the resulting IMAGE_NAME to $BASH_ENV so it is globally available.
            LOWER_USER=$(echo "$GHCR_USERNAME" | tr "[:upper:]" "[:lower:]")
            echo "export IMAGE_NAME=ghcr.io/${LOWER_USER}/just_put_it_notes_service" >> $BASH_ENV

      - run:
          name: Build Docker Image
          command: |
            cd services/notes_service
            docker build -t $IMAGE_NAME:${CIRCLE_SHA1} .
            docker tag $IMAGE_NAME:${CIRCLE_SHA1} $IMAGE_NAME:latest
      
      - run:
          name: Authenticate with GHCR
          command: |
            echo $GHCR_PAT | docker login ghcr.io -u $GHCR_USERNAME --password-stdin
      
      - run:
          name: Push Docker Image to GHCR
          command: |
            docker push $IMAGE_NAME:${CIRCLE_SHA1}
            docker push $IMAGE_NAME:latest

workflows:
  main-workflow:
    jobs:
      - build-and-push:
          filters:
            branches:
              only: main # Triggers the pipeline only on commits to the main branch
```
