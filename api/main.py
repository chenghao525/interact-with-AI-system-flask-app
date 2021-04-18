from flask import Flask, request, Response, jsonify
from flask_cors import CORS, cross_origin

import sqlite3 as sql

import os


app = Flask(__name__)
CORS(app)

@app.route('/start/', methods=['POST'])
@cross_origin()
def start():
    body_decoded = request.get_json()
    consent = body_decoded['consent']

    con = sql.connect(os.path.join(os.getcwd(), 'api/database.db'))
    cur = con.cursor()
    cur.execute('INSERT INTO Consent (consent) VALUES(?)', [consent])

    con.commit()
    msg = "Record successfully added"
    print(msg)

    user_id = cur.execute("SELECT last_insert_rowid()").fetchone()[0]

    response_body = {'user_id': user_id}
    print("user_id=" + str(user_id))
    con.close()

    return jsonify(response_body)


@app.route('/userData/', methods=['POST'])
@cross_origin()
def userData():
    body_decoded = request.get_json()
    userInputTime = body_decoded['userInputTime']
    firstEstimation = body_decoded['firstEstimation']
    updatedEstimation = body_decoded['updatedEstimation']
    
    print("userInputTime: ",userInputTime)
    print("firstEstimation: ",firstEstimation)
    print("updatedEstimation: ",updatedEstimation)

    # print("user input time: ",userInputTime)
    return "1"


if __name__ == "__main__":
    app.run(debug=True)
