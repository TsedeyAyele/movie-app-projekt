import json
import boto3
import uuid
from boto3.dynamodb.conditions import Key
from decimal import Decimal

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('MoviesTable')  # Replace with your actual table name

def lambda_handler(event, context):
    try:
        http_method = event.get("httpMethod", "")

        if http_method == "OPTIONS":
            return generate_response(200, {"message": "CORS preflight success"})

        elif http_method == "GET":
            # Fetch all movies
            response = table.scan()
            movies = response.get("Items", [])
            return generate_response(200, {"movies": decimal_to_native(movies)})

        elif http_method == "POST":
            # Parse request body
            body = json.loads(event["body"])
            title = body.get("title")
            genre = body.get("genre")
            rating = body.get("rating")

            if not title or not genre or not rating:
                return generate_response(400, {"error": "Title, Genre, and Rating are required"})

            # Generate UUID for movieId
            movie_id = str(uuid.uuid4())

            # Insert into DynamoDB
            table.put_item(Item={"movieId": movie_id, "title": title, "genre": genre, "rating": Decimal(str(rating))})
            return generate_response(201, {"message": "Movie added successfully", "movieId": movie_id})

        elif http_method == "PUT":
            body = json.loads(event["body"])
            movie_id = body.get("movieId")
            title = body.get("title")
            genre = body.get("genre")
            rating = body.get("rating")

            if not movie_id:
                return generate_response(400, {"error": "movieId is required"})

            # Check if movie exists
            response = table.get_item(Key={"movieId": movie_id})
            if "Item" not in response:
                return generate_response(404, {"error": "Movie not found"})

            # Update the movie
            update_expression = []
            expression_values = {}

            if title:
                update_expression.append("title = :t")
                expression_values[":t"] = title
            if genre:
                update_expression.append("genre = :g")
                expression_values[":g"] = genre
            if rating:
                update_expression.append("rating = :r")
                expression_values[":r"] = Decimal(str(rating))

            if not update_expression:
                return generate_response(400, {"error": "No fields provided for update"})

            table.update_item(
                Key={"movieId": movie_id},
                UpdateExpression="SET " + ", ".join(update_expression),
                ExpressionAttributeValues=expression_values,
                ReturnValues="UPDATED_NEW"
            )

            return generate_response(200, {"message": "Movie updated successfully"})

        elif http_method == "DELETE":
            movie_id = None
            if "queryStringParameters" in event and event["queryStringParameters"]:
                movie_id = event["queryStringParameters"].get("movieId")
            elif event.get("body"):
                body = json.loads(event["body"])
                movie_id = body.get("movieId")

            if not movie_id:
                return generate_response(400, {"error": "movieId is required"})

            response = table.get_item(Key={"movieId": movie_id})
            if "Item" not in response:
                return generate_response(404, {"error": "Movie not found"})

            table.delete_item(Key={"movieId": movie_id})
            return generate_response(200, {"message": f"Movie with ID {movie_id} deleted successfully"})

        else:
            return generate_response(400, {"error": "Invalid request method"})

    except Exception as e:
        return generate_response(500, {"error": str(e)})

def generate_response(status_code, body):
    """ Helper function to generate a response with CORS headers """
    return {
        "statusCode": status_code,
        "headers": {
            "Access-Control-Allow-Origin": "*",  
            "Access-Control-Allow-Methods": "OPTIONS,GET,POST,PUT,DELETE",
            "Access-Control-Allow-Headers": "Content-Type",
        },
        "body": json.dumps(decimal_to_native(body))
    }

def decimal_to_native(obj):
    """ Convert Decimal objects (from DynamoDB) to native Python types """
    if isinstance(obj, list):
        return [decimal_to_native(i) for i in obj]
    elif isinstance(obj, dict):
        return {k: decimal_to_native(v) for k, v in obj.items()}
    elif isinstance(obj, Decimal):
        return float(obj)  # Convert Decimal to float
    else:
        return obj
