# Small official Python base image
FROM python:3.12-slim

# All following commands run inside /app in the container
WORKDIR /app

# Copy requirements first, so Docker caches the pip install layer.
# If you only change app code, this step is reused and builds are fast.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Now copy the rest of the code
COPY . .

# Don't run as root inside the container (good practice)
RUN useradd --create-home appuser
USER appuser

# Documents the port the app listens on (doesn't publish it)
EXPOSE 5000

# Command that runs when the container starts
CMD ["python", "app.py"]