/*
 *  This file is part of BoxBox (https://github.com/BrightDV/BoxBox).
 * 
 * BoxBox is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * BoxBox is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with BoxBox.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Copyright (c) 2022-2024, BrightDV
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:background_downloader/background_downloader.dart';
import 'package:boxbox/api/brightcove.dart';
import 'package:boxbox/api/driver_components.dart';
import 'package:boxbox/api/race_components.dart';
import 'package:boxbox/api/team_components.dart';
import 'package:boxbox/api/videos.dart';
import 'package:boxbox/helpers/convert_ergast_and_formula_one.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class Formula1 {
  final String defaultEndpoint = "https://api.formula1.com";
  final String apikey = "qPgPPRJyGCIPxFT3el4MF7thXHyJCzAP";

  List<News> formatResponse(Map responseAsJson) {
    bool useDataSaverMode = Hive.box('settings')
        .get('useDataSaverMode', defaultValue: false) as bool;

    List finalJson = responseAsJson['items'];
    List<News> newsList = [];

    for (var element in finalJson) {
      element['title'] = element['title'].replaceAll("\n", "");
      if (element['metaDescription'] != null) {
        element['metaDescription'] =
            element['metaDescription'].replaceAll("\n", "");
      }
      String imageUrl = "";
      if (element['thumbnail'] != null) {
        imageUrl = element['thumbnail']['image']['url'];
        if (useDataSaverMode) {
          if (element['thumbnail']['image']['renditions'] != null) {
            imageUrl =
                element['thumbnail']['image']['renditions']['2col-retina'];
          } else {
            imageUrl += '.transform/2col-retina/image.jpg';
          }
        }
      }

      newsList.add(
        News(
          element['id'],
          element['articleType'],
          element['slug'],
          element['title'],
          element['metaDescription'] ?? '',
          DateTime.parse(element['updatedAt']),
          imageUrl,
        ),
      );
    }
    return newsList;
  }

  FutureOr<List<News>> getMoreNews(
    int offset, {
    String? tagId,
    String? articleType,
  }) async {
    Uri url;
    String endpoint = Hive.box('settings')
        .get('server', defaultValue: defaultEndpoint) as String;
    if (tagId != null) {
      url = Uri.parse(
          '$endpoint/v1/editorial/articles?limit=16&offset=$offset&tags=$tagId');
    } else if (articleType != null) {
      url = Uri.parse(
          '$endpoint/v1/editorial/articles?limit=16&offset=$offset&articleTypes=$articleType');
    } else {
      url =
          Uri.parse('$endpoint/v1/editorial/articles?limit=16&offset=$offset');
    }
    var response = await http.get(
      url,
      headers: endpoint != defaultEndpoint
          ? {
              "Accept": "application/json",
            }
          : {
              "Accept": "application/json",
              "apikey": apikey,
              "locale": "en",
            },
    );

    Map<String, dynamic> responseAsJson =
        json.decode(utf8.decode(response.bodyBytes));
    if (offset == 0 && tagId == null && articleType == null) {
      Hive.box('requests').put('news', responseAsJson);
    }
    return formatResponse(responseAsJson);
  }

  Future<Map<String, dynamic>> getRawPersonalizedFeed(
    List tags, {
    String? articleType,
  }) async {
    Uri url;
    String endpoint = Hive.box('settings')
        .get('server', defaultValue: defaultEndpoint) as String;
    if (articleType != null) {
      url = Uri.parse(
        '$endpoint/v1/editorial/articles?limit=16&tags=${tags.join(',')}&articleTypes=$articleType',
      );
    } else {
      url = Uri.parse(
          '$endpoint/v1/editorial/articles?limit=16&tags=${tags.join(',')}');
    }
    var response = await http.get(
      url,
      headers: endpoint != defaultEndpoint
          ? {
              "Accept": "application/json",
            }
          : {
              "Accept": "application/json",
              "apikey": apikey,
              "locale": "en",
            },
    );

    Map<String, dynamic> responseAsJson =
        json.decode(utf8.decode(response.bodyBytes));
    return responseAsJson;
  }

  Future<Article> getArticleData(String articleId) async {
    String endpoint = Hive.box('settings')
        .get('server', defaultValue: defaultEndpoint) as String;
    Uri url = Uri.parse('$endpoint/v1/editorial/articles/$articleId');
    var response = await http.get(
      url,
      headers: endpoint != defaultEndpoint
          ? {
              "Accept": "application/json",
            }
          : {
              "Accept": "application/json",
              "apikey": apikey,
              "locale": "en",
            },
    );
    Map<String, dynamic> responseAsJson = json.decode(
      utf8.decode(response.bodyBytes),
    );

    Article article = Article(
      responseAsJson['id'],
      responseAsJson['slug'],
      responseAsJson['title'],
      DateTime.parse(responseAsJson['createdAt']),
      responseAsJson['articleTags'],
      responseAsJson['hero'] ?? {},
      responseAsJson['body'],
      responseAsJson['relatedArticles'],
      responseAsJson['author'] ?? {},
    );
    return article;
  }

  Future<String> downloadArticle(String articleId, String articleTitle,
      {Function(TaskStatusUpdate)? callback}) async {
    String endpoint = Hive.box('settings')
        .get('server', defaultValue: defaultEndpoint) as String;

    bool isDownloaded = await downloadedFileCheck('article_$articleId');

    if (!isDownloaded) {
      FileDownloader().unregisterCallbacks(callback: callback);
      if (callback != null) {
        FileDownloader().registerCallbacks(taskStatusCallback: callback);
      }

      final task = DownloadTask(
        taskId: 'article_$articleId',
        url: '$endpoint/v1/editorial/articles/$articleId',
        filename: 'article_$articleId.json',
        displayName: articleTitle,
        headers: endpoint != defaultEndpoint
            ? {
                "Accept": "application/json",
              }
            : {
                "Accept": "application/json",
                "apikey": apikey,
                "locale": "en",
              },
        //directory: 'Box, Box! Downloads',
        updates: Updates.statusAndProgress,
        //requiresWiFi: true,
        retries: 5,
        allowPause: true,
      );

      final successfullyEnqueued = await FileDownloader().enqueue(task);

      if (successfullyEnqueued) {
        List downloads = Hive.box('downloads').get(
          'downloadsList',
          defaultValue: [],
        );
        downloads.insert(0, 'article_$articleId');
        Hive.box('downloads').put('downloadsList', downloads);
        return "downloading";
      } else {
        return "not downloaded";
      }
    } else {
      return "already downloaded";
    }
  }

  Future<String> downloadVideo(
    String videoId,
    String quality, {
    Video? video,
    Function(TaskStatusUpdate)? callback,
  }) async {
    bool isDownloaded = await downloadedFileCheck('video_$videoId');

    if (!isDownloaded) {
      FileDownloader().unregisterCallbacks(callback: callback);
      if (callback != null) {
        FileDownloader().registerCallbacks(taskStatusCallback: callback);
      }
      if (video == null) {
        video = await F1VideosFetcher().getVideoDetails(videoId);
      }

      Map links = await BrightCove().getVideoLinks(videoId);
      String link =
          links['videos'][links['qualities'].indexOf('${quality}p') + 1];
      // index 0 is preferred quality

      Map videoDetails = {
        'id': video.videoId,
        'title': video.caption,
        'thumbnail': video.thumbnailUrl,
        'url': video.videoUrl,
        'description': video.description,
        'videoDuration': video.videoDuration,
        'datePosted': video.datePosted.toIso8601String(),
      };

      final task = DownloadTask(
        taskId: 'video_$videoId',
        url: link,
        filename: 'video_$videoId.mp4',
        displayName: video.caption,
        //directory: 'Box, Box! Downloads',
        updates: Updates.statusAndProgress,
        //requiresWiFi: true,
        retries: 3,
        allowPause: true,
        metaData: json.encode(videoDetails),
      );

      final successfullyEnqueued = await FileDownloader().enqueue(task);

      if (successfullyEnqueued) {
        List downloads = Hive.box('downloads').get(
          'downloadsList',
          defaultValue: [],
        );
        downloads.insert(0, 'video_$videoId');
        Hive.box('downloads').put('downloadsList', downloads);
        return "downloading";
      } else {
        return "not downloaded";
      }
    } else {
      return "already downloaded";
    }
  }

  Future<bool> downloadedFileCheck(String taskId) async {
    final record = await FileDownloader().database.recordForId(taskId);
    if (record != null) {
      return true;
    } else {
      return false;
    }
  }

  Future<String?> downloadedFilePathIfExists(String taskId) async {
    final record = await FileDownloader().database.recordForId(taskId);
    if (record != null) {
      return await record.task.filePath();
    } else {
      return null;
    }
  }

  Future<void> deleteFile(String taskId) async {
    final record = await FileDownloader().database.recordForId(taskId);
    if (record != null) {
      // delete download taskId
      List downloads = await Hive.box('downloads').get(
        'downloadsList',
        defaultValue: [],
      );
      downloads.remove(taskId);
      await Hive.box('requests').put('downloadsList', downloads);
      // delete download record
      await FileDownloader().database.deleteRecordWithId(taskId);
      // delete download description
      Map downloadsDescriptions = Hive.box('downloads').get(
        'downloadsDescriptions',
        defaultValue: {},
      );
      downloadsDescriptions.remove(taskId);
      await Hive.box('downloads')
          .put('downloadsDescriptions', downloadsDescriptions);
      String filePath = await record.task.filePath();
      // delete file from device
      await File(filePath).delete();
    }
  }

  Future<bool> saveLoginCookie(String cookieValue) async {
    String cookies = 'reese84=$cookieValue;';
    String body =
        '{"Login": "${utf8.decode(base64.decode('eWlrbmFib2RyYUBndWZ1bS5jb20='))}","Password": "${utf8.decode(base64.decode('UGxlYXNlRG9uJ3RTdGVhbCExMjM='))}","DistributionChannel": "d861e38f-05ea-4063-8776-a7e2b6d885a4"}';

    Uri url = Uri.parse(
        '$defaultEndpoint/v2/account/subscriber/authenticate/by-password');

    var response = await http.post(
      url,
      body: body,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:124.0) Gecko/20100101 Firefox/124.0',
        'Origin': 'https://account.formula1.com',
        'Referer': 'https://account.formula1.com/',
        'Host': 'api.formula1.com',
        'Sec-Fetch-Dest': 'empty',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'same-site',
        'Sec-GPC': '1',
        'Connection': 'keep-alive',
        'Content-Length': '130',
        'DNT': '1',
        'apiKey': 'fCUCjWrKPu9ylJwRAv8BpGLEgiAuThx7',
        'Accept': 'application/json, text/javascript, */*; q=0.01',
        'Accept-Encoding': 'gzip, deflate, br',
        'Content-Type': 'application/json',
        'Cookie': cookies,
      },
    );

    if (response.statusCode == '403') {
      Hive.box('requests').put('webViewCookie', '');
      Hive.box('requests').put('loginCookie', '');
      return false;
    }

    Map<String, dynamic> responseAsJson = json.decode(
      utf8.decode(response.bodyBytes),
    );

    String token = responseAsJson['data']['subscriptionToken'];
    String loginCookie = '{"data": {"subscriptionToken":"$token"}}';
    Hive.box('requests').put('loginCookie', loginCookie);
    Hive.box('requests').put('loginCookieLatestQuery', DateTime.now());

    return true;
  }

  List<DriverResult> formatRaceStandings(Map raceStandings) {
    List<DriverResult> formatedRaceStandings = [];
    List jsonResponse = raceStandings['raceResultsRace']['results'];
    String time;
    String fastestLapDriverName = "";
    String fastestLapTime = "";
    for (var award in raceStandings["raceResultsRace"]["awards"]) {
      // find fastest_lap award, as its index may not be static
      if (award['type'].toLowerCase() == 'fastest_lap') {
        fastestLapDriverName = award['winnerName'];
        fastestLapTime = award['winnerTime'];
        break;
      }
    }
    for (var element in jsonResponse) {
      if (element['completionStatusCode'] != 'OK') {
        // DNF (maybe DSQ?)
        time = element['completionStatusCode'];
      } else if (element['positionNumber'] == '1') {
        time = element['raceTime'];
      } else if (element['lapsBehindLeader'] != null) {
        // finished & lapped cars
        if (element['lapsBehindLeader'] == "0") {
          time = "+" + element['gapToLeader'];
          if (time.substring(time.indexOf('.') + 1).length == 2) {
            time += "0";
          }
        } else if (element['lapsBehindLeader'] == "1") {
          // one
          time = "+1 Lap";
        } else {
          // more laps
          time = "+${element['lapsBehindLeader']} Laps";
        }
      } else {
        // finished & non-lapped cars
        if (element['positionNumber'] == "1") {
          //first
          time = element["raceTime"];
        } else {
          time = element["gapToLeader"];
          if (time.substring(time.indexOf('.') + 1).length == 2) {
            time += "0";
          }
        }
      }

      String fastestLapRank = "0";
      if (element['driverLastName'].toLowerCase() ==
          fastestLapDriverName.toLowerCase()) {
        fastestLapRank = "1";
      }
      formatedRaceStandings.add(
        DriverResult(
          // TODO: find another driverId?
          '', //element['Driver']['driverId'],
          element['positionNumber'],
          element['racingNumber'],
          element['driverFirstName'],
          element['driverLastName'],
          element['driverTLA'],
          Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
          time,
          fastestLapRank != '0' ? true : false,
          fastestLapRank != '0' ? fastestLapTime : "",
          "", // data not available
          points: element['racePoints'].toString(),
          status: element['completionStatusCode'],
        ),
      );
    }
    return formatedRaceStandings;
  }

  FutureOr<List<DriverResult>> getRaceStandings(
      String meetingId, String round) async {
    Map results = Hive.box('requests').get('race-$round', defaultValue: {});
    DateTime latestQuery = Hive.box('requests').get(
      'race-$round-latestQuery',
      defaultValue: DateTime.now(),
    ) as DateTime;
    String raceResultsLastSavedFormat = Hive.box('requests')
        .get('raceResultsLastSavedFormat', defaultValue: 'ergast');

    if (latestQuery
            .add(
              const Duration(minutes: 5),
            )
            .isAfter(DateTime.now()) &&
        results.isNotEmpty &&
        raceResultsLastSavedFormat == 'f1') {
      return formatRaceStandings(results);
    } else {
      var url = Uri.parse(
        '$defaultEndpoint/v1/fom-results/race?meeting=$meetingId',
      );
      var response = await http.get(
        url,
        headers: {
          "Accept": "application/json",
          "apikey": apikey,
          "locale": "en",
        },
      );
      Map<String, dynamic> responseAsJson = jsonDecode(response.body);
      List<DriverResult> driversResults = formatRaceStandings(responseAsJson);
      Hive.box('requests').put('raceResultsLastSavedFormat', 'f1');
      Hive.box('requests').put('race-$round', responseAsJson);
      Hive.box('requests').put(
        'race-$round-latestQuery',
        DateTime.now(),
      );

      return driversResults;
    }
  }

  FutureOr<List<DriverQualificationResult>> getQualificationStandings(
      String meetingId) async {
    List<DriverQualificationResult> driversResults = [];
    var url = Uri.parse(
      '$defaultEndpoint/v1/fom-results/qualifying?meeting=$meetingId',
    );
    var response = await http.get(
      url,
      headers: {
        "Accept": "application/json",
        "apikey": apikey,
        "locale": "en",
      },
    );
    Map<String, dynamic> responseAsJson = jsonDecode(response.body);
    if (responseAsJson['raceResultsQualifying']['state'] != 'completed') {
      return [];
    } else {
      List finalJson = responseAsJson['raceResultsQualifying']['results'];
      for (var element in finalJson) {
        driversResults.add(
          DriverQualificationResult(
            '',
            element['positionNumber'],
            element['racingNumber'],
            element['driverFirstName'],
            element['driverLastName'],
            element['driverTLA'],
            Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
            element['q1']['completionStatusCode'] != 'OK'
                ? element['q1']['completionStatusCode']
                : element['q1']['classifiedTime'],
            element['q2'] == null
                ? '--'
                : element['q2']['completionStatusCode'] != 'OK'
                    ? element['q2']['completionStatusCode']
                    : element['q2']['classifiedTime'],
            element['q3'] == null
                ? '--'
                : element['q3']['completionStatusCode'] != 'OK'
                    ? element['q3']['completionStatusCode']
                    : element['q3']['classifiedTime'],
          ),
        );
      }

      return driversResults;
    }
  }

  Future<List<DriverResult>> getFreePracticeStandings(
      String meetingId, int session) async {
    List<DriverResult> driversResults = [];
    var url = Uri.parse(
      '$defaultEndpoint/v1/fom-results/practice?meeting=$meetingId&session=$session',
    );
    var response = await http.get(
      url,
      headers: {
        "Accept": "application/json",
        "apikey": apikey,
        "locale": "en",
      },
    );
    Map<String, dynamic> responseAsJson = jsonDecode(response.body);
    if (responseAsJson['raceResultsPractice$session']['state'] != 'completed') {
      return [];
    } else {
      List finalJson = responseAsJson['raceResultsPractice$session']['results'];
      for (var element in finalJson) {
        String time = "";
        if (element['gapToLeader'] != null) {
          time = '+' + element['gapToLeader'];
          if (time.substring(time.indexOf('.') + 1).length == 2) {
            time += '0';
          }
          time += 's';
        }

        driversResults.add(
          DriverResult(
            // TODO: find another driverId?
            '',
            element['positionNumber'],
            element['racingNumber'],
            element['driverFirstName'],
            element['driverLastName'],
            element['driverTLA'],
            Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
            element['classifiedTime'] ?? '',
            false,
            "",
            time,
            lapsDone: element['lapsCompleted'],
            points: element['racePoints'].toString(),
            status: element['completionStatusCode'],
          ),
        );
      }

      return driversResults;
    }
  }

  FutureOr<List<DriverQualificationResult>> getSprintQualifyingStandings(
      String meetingId) async {
    List<DriverQualificationResult> driversResults = [];
    var url = Uri.parse(
      '$defaultEndpoint/v1/fom-results/sprint-shootout?meeting=$meetingId',
    );
    var response = await http.get(
      url,
      headers: {
        "Accept": "application/json",
        "apikey": apikey,
        "locale": "en",
      },
    );
    Map<String, dynamic> responseAsJson = jsonDecode(response.body);
    if (responseAsJson['raceResultsSprintShootout']['state'] != 'completed') {
      return [];
    } else {
      List finalJson = responseAsJson['raceResultsSprintShootout']['results'];
      for (var element in finalJson) {
        driversResults.add(
          DriverQualificationResult(
            '',
            element['positionNumber'],
            element['racingNumber'],
            element['driverFirstName'],
            element['driverLastName'],
            element['driverTLA'],
            Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
            element['q1']['completionStatusCode'] != 'OK'
                ? element['q1']['completionStatusCode']
                : element['q1']['classifiedTime'],
            element['q2'] == null
                ? '--'
                : element['q2']['completionStatusCode'] != 'OK'
                    ? element['q2']['completionStatusCode']
                    : element['q2']['classifiedTime'],
            element['q3'] == null
                ? '--'
                : element['q3']['completionStatusCode'] != 'OK'
                    ? element['q3']['completionStatusCode']
                    : element['q3']['classifiedTime'],
          ),
        );
      }

      return driversResults;
    }
  }

  FutureOr<List<DriverResult>> getSprintStandings(
      String meetingId, String session) async {
    List<DriverResult> driversResults = [];
    String time;
    var url = Uri.parse(
      '$defaultEndpoint/v1/fom-results/sprint?meeting=$meetingId',
    );
    var response = await http.get(
      url,
      headers: {
        "Accept": "application/json",
        "apikey": apikey,
        "locale": "en",
      },
    );
    Map<String, dynamic> responseAsJson = jsonDecode(response.body);
    if (responseAsJson['raceResultsSprint']['state'] != 'completed') {
      return [];
    } else {
      List finalJson = responseAsJson['raceResultsSprint']['results'];
      for (var element in finalJson) {
        if (element['completionStatusCode'] != 'OK') {
          // DNF (maybe DSQ?)
          time = element['completionStatusCode'];
        } else if (element['positionNumber'] == '1') {
          // first
          time = element['sprintQualifyingTime'];
        } else if (element['lapsBehindLeader'] != null) {
          // finished & lapped? cars
          if (element['lapsBehindLeader'] == "0") {
            time = "+" + element['gapToLeader'];
            if (time.substring(time.indexOf('.') + 1).length == 2) {
              time += "0";
            }
          } else if (element['lapsBehindLeader'] == "1") {
            // one
            time = "+1 Lap";
          } else {
            // more laps
            time = "+${element['lapsBehindLeader']} Laps";
          }
        } else {
          time = element["gapToLeader"];
          if (time.substring(time.indexOf('.') + 1).length == 2) {
            time += "0";
          }
        }
        driversResults.add(
          DriverResult(
            // TODO: find another driverId?
            '',
            element['positionNumber'],
            element['racingNumber'],
            element['driverFirstName'],
            element['driverLastName'],
            element['driverTLA'],
            Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
            time,
            false,
            time,
            time,
            lapsDone: "NA",
            points: element['sprintQualifyingPoints'].toString(),
            status: element['completionStatusCode'],
          ),
        );
      }

      return driversResults;
    }
  }

  List<Driver> formatLastStandings(Map responseAsJson) {
    List<Driver> drivers = [];
    List finalJson = responseAsJson['drivers'];
    for (var element in finalJson) {
      String detailsPath =
          element['driverPageUrl'].split('/').last.split('.').first;
      drivers.add(
        Driver(
          Convert().driverIdFromFormula1(detailsPath),
          element['positionNumber'],
          element['racingNumber'],
          element['driverFirstName'],
          element['driverLastName'],
          element['driverTLA'],
          Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
          element['championshipPoints'].toString(),
          driverImage: element['driverImage'],
          detailsPath: detailsPath,
          teamColor: Color(
            int.parse(
              'FF' + element['teamColourCode'],
              radix: 16,
            ),
          ),
        ),
      );
    }
    return drivers;
  }

  FutureOr<List<Driver>> getLastStandings() async {
    Map driverStandings =
        Hive.box('requests').get('driversStandings', defaultValue: {});
    DateTime latestQuery = Hive.box('requests').get(
      'driversStandingsLatestQuery',
      defaultValue: DateTime.now(),
    ) as DateTime;
    String driverStandingsLastSavedFormat = Hive.box('requests')
        .get('driverStandingsLastSavedFormat', defaultValue: 'ergast');

    if (latestQuery
            .add(
              const Duration(minutes: 30),
            )
            .isAfter(DateTime.now()) &&
        driverStandings.isNotEmpty &&
        driverStandingsLastSavedFormat == 'f1') {
      return formatLastStandings(driverStandings);
    } else {
      var url = Uri.parse(
        '$defaultEndpoint/v1/editorial-driverlisting/listing',
      );
      var response = await http.get(
        url,
        headers: {
          "Accept": "application/json",
          "apikey": apikey,
          "locale": "en",
        },
      );
      Map<String, dynamic> responseAsJson = jsonDecode(response.body);
      List<Driver> drivers = formatLastStandings(responseAsJson);
      Hive.box('requests').put('driversStandings', responseAsJson);
      Hive.box('requests').put('driversStandingsLatestQuery', DateTime.now());
      Hive.box('requests').put('driverStandingsLastSavedFormat', 'f1');
      return drivers;
    }
  }

  List<Team> formatLastTeamsStandings(Map responseAsJson) {
    List<Team> drivers = [];
    List finalJson = responseAsJson['constructors'];
    for (var element in finalJson) {
      String detailsPath =
          element['teamPageUrl'].split('/').last.split('.').first;
      drivers.add(
        Team(
          Convert().teamsFromFormulaOneApiToErgast(element['teamName']),
          element['positionNumber'],
          element['teamName'],
          element['seasonPoints'].toString(),
          'NA',
          teamCarImage: element['teamImage'],
          teamCarImageCropped: element['teamCroppedImage'],
          detailsPath: detailsPath,
          teamColor: Color(
            int.parse(
              'FF' + element['teamColourCode'],
              radix: 16,
            ),
          ),
        ),
      );
    }
    return drivers;
  }

  FutureOr<List<Team>> getLastTeamsStandings() async {
    Map teamsStandings =
        Hive.box('requests').get('teamsStandings', defaultValue: {});
    DateTime latestQuery = Hive.box('requests').get(
      'teamsStandingsLatestQuery',
      defaultValue: DateTime.now(),
    ) as DateTime;
    String teamStandingsLastSavedFormat = Hive.box('requests')
        .get('teamStandingsLastSavedFormat', defaultValue: 'ergast');

    if (latestQuery
            .add(
              const Duration(minutes: 10),
            )
            .isAfter(DateTime.now()) &&
        teamsStandings.isNotEmpty &&
        teamStandingsLastSavedFormat == 'f1') {
      return formatLastTeamsStandings(teamsStandings);
    } else {
      var url = Uri.parse(
        '$defaultEndpoint/v1/editorial-constructorlisting/listing',
      );
      var response = await http.get(
        url,
        headers: {
          "Accept": "application/json",
          "apikey": apikey,
          "locale": "en",
        },
      );
      Map<String, dynamic> responseAsJson = jsonDecode(response.body);
      List<Team> teams = formatLastTeamsStandings(responseAsJson);
      Hive.box('requests').put('teamsStandings', responseAsJson);
      Hive.box('requests').put('teamsStandingsLatestQuery', DateTime.now());
      Hive.box('requests').put('teamStandingsLastSavedFormat', 'f1');
      return teams;
    }
  }

  List<Race> formatLastSchedule(Map responseAsJson, bool toCome) {
    List<Race> races = [];
    List finalJson = responseAsJson['events'];
    if (toCome) {
      for (var element in finalJson) {
        DateTime raceEndDate =
            DateTime.parse(element['meetingEndDate'] + element['gmtOffset'])
                .toLocal();
        DateTime raceDate =
            DateTime.parse(element['meetingEndDate'] + element['gmtOffset'])
                .toLocal()
                .subtract(Duration(hours: 3));
        DateTime now = DateTime.now();

        if (now.compareTo(raceEndDate) < 0) {
          String detailsPath = element['url'].split('/').last.split('.').first;
          if (element['meetingCountryName'] == 'Emilia-Romagna') {
            detailsPath = 'EmiliaRomagna';
          } else if (element['meetingCountryName'] == 'Miami') {
            detailsPath = 'Miami';
          } else if (element['meetingCountryName'] == 'Great Britain') {
            detailsPath = 'Great_Britain';
          } else if (element['meetingCountryName'] == 'Las Vegas') {
            detailsPath = 'Las_Vegas';
          }
          races.add(
            Race(
              finalJson.indexOf(element).toString(),
              element['meetingKey'],
              element['meetingName'],
              element['meetingEndDate'] + element['gmtOffset'],
              DateFormat.Hm().format(raceDate),
              element['meetingLocation'],
              element['meetingLocation'],
              '',
              element['meetingCountryName'],
              [],
              isFirst: races.isEmpty,
              raceCoverUrl: element['thumbnail']['image']['url'],
              detailsPath: detailsPath,
            ),
          );
        }
      }
    } else {
      for (var element in finalJson) {
        DateTime raceEndDate =
            DateTime.parse(element['meetingEndDate'] + element['gmtOffset'])
                .toLocal();
        DateTime raceDate =
            DateTime.parse(element['meetingEndDate'] + element['gmtOffset'])
                .subtract(Duration(hours: 3))
                .toLocal();
        DateTime now = DateTime.now();

        if (now.compareTo(raceEndDate) > 0) {
          String detailsPath = element['url'].split('/').last.split('.').first;
          if (element['meetingCountryName'] == 'Emilia-Romagna') {
            detailsPath = 'EmiliaRomagna';
          } else if (element['meetingCountryName'] == 'Miami') {
            detailsPath = 'Miami';
          } else if (element['meetingCountryName'] == 'United Kingdom') {
            detailsPath = 'Great_Britain';
          } else if (element['meetingCountryName'] == 'Las Vegas') {
            detailsPath = 'Las_Vegas';
          }
          races.add(
            Race(
              finalJson.indexOf(element).toString(),
              element['meetingKey'],
              element['meetingName'],
              element['meetingEndDate'] + element['gmtOffset'],
              DateFormat.Hm().format(raceDate),
              element['meetingLocation'],
              element['meetingLocation'],
              '',
              element['meetingCountryName'],
              [],
              isFirst: races.isEmpty,
              raceCoverUrl: element['thumbnail']['image']['url'],
              detailsPath: detailsPath,
            ),
          );
        }
      }
    }
    return races;
  }

  Future<List<Race>> getLastSchedule(bool toCome) async {
    Map schedule = Hive.box('requests').get('schedule', defaultValue: {});
    DateTime latestQuery = Hive.box('requests').get(
      'scheduleLatestQuery',
      defaultValue: DateTime.now().subtract(
        const Duration(hours: 1),
      ),
    ) as DateTime;
    String scheduleLastSavedFormat = Hive.box('requests')
        .get('scheduleLastSavedFormat', defaultValue: 'ergast');

    if (latestQuery
            .add(
              const Duration(minutes: 30),
            )
            .isAfter(DateTime.now()) &&
        schedule.isNotEmpty &&
        scheduleLastSavedFormat == 'f1') {
      return formatLastSchedule(schedule, toCome);
    } else {
      var url = Uri.parse('$defaultEndpoint/v1/editorial-eventlisting/events');
      var response = await http.get(
        url,
        headers: {
          "Accept": "application/json",
          "apikey": apikey,
          "locale": "en",
        },
      );
      Map<String, dynamic> responseAsJson = json.decode(
        utf8.decode(response.bodyBytes),
      );
      List<Race> races = formatLastSchedule(responseAsJson, toCome);
      Hive.box('requests').put('schedule', responseAsJson);
      Hive.box('requests').put('scheduleLatestQuery', DateTime.now());
      Hive.box('requests').put('scheduleLastSavedFormat', 'f1');
      return races;
    }
  }

  Future<List> getStartingGrid(String meetingId) async {
    var url = Uri.parse(
      '$defaultEndpoint/v1/fom-results/starting-grid?meeting=$meetingId',
    );
    var response = await http.get(
      url,
      headers: {
        "Accept": "application/json",
        "apikey": apikey,
        "locale": "en",
      },
    );
    Map<String, dynamic> responseAsJson = json.decode(
      utf8.decode(response.bodyBytes),
    );

    List<StartingGridPosition> results = [];

    for (var result in responseAsJson['startingGrid']) {
      results.add(
        StartingGridPosition(
          result['positionNumber'],
          result['positionNumber'],
          result['driverLastName'],
          Convert().teamsFromFormulaOneApiToErgast(
            result['teamName'],
          ),
          result['teamName'],
          result['classifiedTime'] != null ? result['classifiedTime'] : '--',
        ),
      );
    }

    return [results, responseAsJson['startingGridFootnote'] ?? ''];
  }
}

class News {
  final String newsId;
  final String newsType;
  final String slug;
  final String title;
  final String subtitle;
  final DateTime datePosted;
  final String imageUrl;

  News(
    this.newsId,
    this.newsType,
    this.slug,
    this.title,
    this.subtitle,
    this.datePosted,
    this.imageUrl,
  );
}

class Article {
  final String articleId;
  final String articleSlug;
  final String articleName;
  final DateTime publishedDate;
  final List articleTags;
  final Map articleHero;
  final List articleContent;
  final List relatedArticles;
  final Map authorDetails;

  Article(
    this.articleId,
    this.articleSlug,
    this.articleName,
    this.publishedDate,
    this.articleTags,
    this.articleHero,
    this.articleContent,
    this.relatedArticles,
    this.authorDetails,
  );
}
