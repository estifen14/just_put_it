package com.justputit.notes.auth;

import java.time.Instant;
import java.util.Map;

public class ApiErrorResponse {
    
    private Instant timestamp;
    private int status;
    private String error;
    private String message;
    private Map<String, String> validationErrors;

    public ApiErrorResponse(int status, String error, String message) {
        this.timestamp = Instant.now();
        this.status = status;
        this.error = error;
        this.message = message;
    }

    public ApiErrorResponse(int status, String error, String message, Map<String, String> validationErrors) {
        this(status, error, message);
        this.validationErrors = validationErrors;
    }

    public Instant getTimestamp() { return timestamp; }
    public int getStatus() { return status; }
    public String getError() { return error; }
    public String getMessage() { return message; }
    public Map<String, String> getValidationErrors() { return validationErrors; }
}
