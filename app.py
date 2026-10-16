from flask import Flask

app = Flask(__name__)

@app.route("/")
def hello():
    return "Goodbye from my DevOps lab!"

@app.route("/health")
def health():
    return {"status": "ok"}

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)