import base64
import os

from flask import Flask, jsonify, request
from google.api_core.client_options import ClientOptions
from google.cloud import documentai


app = Flask(__name__)


PROJECT_ID = os.environ["DOCUMENTAI_PROJECT_ID"]
LOCATION = os.environ.get("DOCUMENTAI_LOCATION", "us")
PROCESSOR_ID = os.environ["DOCUMENTAI_PROCESSOR_ID"]

client_options = ClientOptions(api_endpoint=f"{LOCATION}-documentai.googleapis.com")
documentai_client = documentai.DocumentProcessorServiceClient(
    client_options=client_options
)
PROCESSOR_NAME = documentai_client.processor_path(PROJECT_ID, LOCATION, PROCESSOR_ID)


def _error(message: str, status: int):
    return jsonify({"error": message}), status


def _require_api_key():
    expected = os.environ.get("OCR_API_KEY")
    if not expected:
        return None

    provided = request.headers.get("X-API-Key")
    if provided != expected:
        return _error("missing or invalid X-API-Key header", 401)

    return None


def _document_from_request():
    if "file" in request.files:
        upload = request.files["file"]
        content_type = upload.mimetype or "application/pdf"
        return upload.read(), content_type

    if request.is_json:
        payload = request.get_json(silent=True) or {}
        document_base64 = payload.get("document_base64")
        if document_base64:
            try:
                content = base64.b64decode(document_base64, validate=True)
            except ValueError:
                raise ValueError("document_base64 is not valid base64") from None
            return content, payload.get("mime_type", "application/pdf")

    return None, None


@app.get("/health")
def health():
    return jsonify({"status": "ok"})


@app.post("/ocr")
def ocr():
    auth_error = _require_api_key()
    if auth_error:
        return auth_error

    try:
        content, mime_type = _document_from_request()
    except ValueError as exc:
        return _error(str(exc), 400)

    if not content:
        return _error("send a document as multipart file or JSON document_base64", 400)

    raw_document = documentai.RawDocument(content=content, mime_type=mime_type)
    response = documentai_client.process_document(
        request=documentai.ProcessRequest(
            name=PROCESSOR_NAME,
            raw_document=raw_document,
        )
    )
    document = response.document
    return jsonify(
        {
            "mime_type": mime_type,
            "pages": len(document.pages),
            "text": document.text,
        }
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
