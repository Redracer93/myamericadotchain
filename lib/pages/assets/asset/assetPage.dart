import 'package:app/pages/assets/asset/locksDetailPage.dart';
import 'package:app/pages/assets/transfer/detailPage.dart';
import 'package:app/pages/assets/transfer/transferPage.dart';
import 'package:app/service/index.dart';
import 'package:app/store/types/transferData.dart';
import 'package:app/utils/ShowCustomAlterWidget.dart';
import 'package:app/utils/i18n/index.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:polkawallet_sdk/api/subscan.dart';
import 'package:polkawallet_sdk/api/types/balanceData.dart';
import 'package:polkawallet_sdk/utils/i18n.dart';
import 'package:polkawallet_ui/components/TransferIcon.dart';
import 'package:polkawallet_ui/components/listTail.dart';
import 'package:polkawallet_ui/components/txButton.dart';
import 'package:polkawallet_ui/components/v3/back.dart';
import 'package:polkawallet_ui/components/v3/borderedTitle.dart';
import 'package:polkawallet_ui/components/v3/index.dart' as v3;
import 'package:polkawallet_ui/pages/accountQrCodePage.dart';
import 'package:polkawallet_ui/pages/txConfirmPage.dart';
import 'package:polkawallet_ui/utils/format.dart';
import 'package:polkawallet_ui/utils/i18n.dart';
import 'package:polkawallet_ui/utils/index.dart';

class AssetPage extends StatefulWidget {
  AssetPage(this.service);
  final AppService service;

  static final String route = '/assets/detail';

  @override
  _AssetPageState createState() => _AssetPageState();
}

class _AssetPageState extends State<AssetPage> {
  final GlobalKey<RefreshIndicatorState> _refreshKey =
      new GlobalKey<RefreshIndicatorState>();

  final colorIn = Color(0xFF62CFE4);
  final colorOut = Color(0xFF3394FF);

  bool _loading = false;

  int _tab = 0;
  String history = 'all';
  int _txsPage = 0;
  bool _isLastPage = false;
  ScrollController _scrollController;

  List _unlocks = [];

  Future<void> _queryDemocracyUnlocks() async {
    final List unlocks = await widget.service.plugin.sdk.api.gov
        .getDemocracyUnlocks(widget.service.keyring.current.address);
    if (mounted && unlocks != null) {
      setState(() {
        _unlocks = unlocks;
      });
    }
  }

  void _onUnlock() async {
    final dic = I18n.of(context).getDic(i18n_full_dic_app, 'assets');
    final txs = _unlocks
        .map(
            (e) => 'api.tx.democracy.removeVote(${BigInt.parse(e.toString())})')
        .toList();
    txs.add(
        'api.tx.democracy.unlock("${widget.service.keyring.current.address}")');
    final res = await Navigator.of(context).pushNamed(TxConfirmPage.route,
        arguments: TxConfirmParams(
            txTitle: dic['lock.unlock'],
            module: 'utility',
            call: 'batch',
            txDisplay: {
              "actions": ['democracy.removeVote', 'democracy.unlock'],
            },
            params: [],
            rawParams: '[[${txs.join(',')}]]'));
    if (res != null) {
      _refreshKey.currentState.show();
    }
  }

  Future<void> _updateData() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });

    widget.service.plugin.updateBalances(widget.service.keyring.current);

    final res = await widget.service.assets.updateTxs(_txsPage);

    if (!mounted) return;
    setState(() {
      _loading = false;
      _txsPage += 1;
    });

    if (res['transfers'] == null ||
        res['transfers'].length < tx_list_page_size) {
      setState(() {
        _isLastPage = true;
      });
    }
  }

  Future<void> _refreshData() async {
    if (widget.service.plugin.sdk.api.connectedNode == null) return;

    if (widget.service.plugin.basic.name == 'polkadot' ||
        widget.service.plugin.basic.name == 'kusama') {
      _queryDemocracyUnlocks();
    }

    setState(() {
      _txsPage = 0;
      _isLastPage = false;
    });

    widget.service.assets.fetchMarketPriceFromSubScan();

    await _updateData();
  }

  void _showAction() async {
    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        actions: <Widget>[
          CupertinoActionSheetAction(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(I18n.of(context)
                    .getDic(i18n_full_dic_app, 'assets')['address.subscan']),
                Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: Theme.of(context).primaryColor,
                  ),
                )
              ],
            ),
            onPressed: () {
              String networkName = widget.service.plugin.basic.name;
              if (widget.service.plugin.basic.isTestNet) {
                networkName = '${networkName.split('-')[0]}-testnet';
              }
              final snLink =
                  'https://$networkName.subscan.io/account/${widget.service.keyring.current.address}';
              UI.launchURL(snLink);
              Navigator.of(context).pop();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: Text(
              I18n.of(context).getDic(i18n_full_dic_ui, 'common')['cancel']),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _scrollController = ScrollController();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent) {
        if (_tab == 0 && !_isLastPage) {
          _updateData();
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Widget> _buildTxList() {
    final symbol = (widget.service.plugin.networkState.tokenSymbol ?? [''])[0];
    final txs = widget.service.store.assets.txs.toList();
    txs.retainWhere((e) {
      switch (_tab) {
        case 1:
          return e.to == widget.service.keyring.current.address;
        case 2:
          return e.from == widget.service.keyring.current.address;
        default:
          return true;
      }
    });
    final List<Widget> res = [];
    res.addAll(txs.map((i) {
      return Column(
        children: [
          TransferListItem(
            data: i,
            token: symbol,
            isOut: i.from == widget.service.keyring.current.address,
            hasDetail: true,
          ),
          Divider(
            height: 1,
          )
        ],
      );
    }));

    res.add(ListTail(
      isEmpty: txs.length == 0,
      isLoading: _loading,
    ));

    return res;
  }

  @override
  Widget build(BuildContext context) {
    final dic = I18n.of(context).getDic(i18n_full_dic_app, 'assets');

    final symbol = (widget.service.plugin.networkState.tokenSymbol ?? [''])[0];
    final decimals =
        (widget.service.plugin.networkState.tokenDecimals ?? [12])[0];

    BalanceData balancesInfo = widget.service.plugin.balances.native;

    // String lockedInfo = '\n';
    bool hasVesting = false;
    if (balancesInfo != null && balancesInfo.lockedBreakdown != null) {
      balancesInfo.lockedBreakdown.forEach((i) {
        final amt = Fmt.balanceInt(i.amount.toString());
        if (amt > BigInt.zero) {
          // lockedInfo += '${Fmt.priceFloorBigInt(
          //   amt,
          //   decimals,
          //   lengthMax: 4,
          // )} $symbol ${dic['lock.${i.use.trim()}']}\n';
          if (i.use.contains('ormlvest')) {
            hasVesting = true;
          }
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          symbol,
          style: TextStyle(fontSize: 20, color: Colors.black87),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackBtn(
          onBack: () => Navigator.of(context).pop(),
        ),
        actions: [
          Padding(
              padding: EdgeInsets.only(right: 16.w),
              child: v3.IconButton(
                  isBlueBg: true,
                  icon: Icon(
                    Icons.more_horiz,
                    color: Theme.of(context).cardColor,
                  ),
                  onPressed: _showAction)),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Observer(
          builder: (_) {
            bool transferEnabled = true;
            if (widget.service.plugin.basic.name == 'karura' ||
                widget.service.plugin.basic.name == 'acala') {
              transferEnabled = false;
              if (widget.service.store.settings.liveModules['assets'] != null) {
                transferEnabled = widget
                    .service.store.settings.liveModules['assets']['enabled'];
              }
            }

            BalanceData balancesInfo = widget.service.plugin.balances.native;
            return Column(
              children: <Widget>[
                BalanceCard(
                  balancesInfo,
                  symbol: symbol,
                  decimals: decimals,
                  marketPrices: widget.service.store.assets.marketPrices,
                  backgroundImage: widget.service.plugin.basic.backgroundImage,
                  unlocks: _unlocks,
                  onUnlock: _onUnlock,
                  icon: widget.service.plugin.tokenIcons[symbol],
                ),
                Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 18.h),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            child: CarButton(
                              icon: SvgPicture.asset("assets/images/send.svg",
                                  color: Theme.of(context)
                                      .textSelectionTheme
                                      .selectionColor,
                                  width: 24),
                              text: dic['v3.send'],
                              onPressed: transferEnabled
                                  ? () {
                                      Navigator.pushNamed(
                                        context,
                                        TransferPage.route,
                                        arguments: TransferPageParams(
                                          redirect: AssetPage.route,
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            child: CarButton(
                              icon: SvgPicture.asset("assets/images/qr.svg",
                                  color: Theme.of(context)
                                      .textSelectionTheme
                                      .selectionColor,
                                  width: 24),
                              text: dic['receive'],
                              onPressed: () {
                                Navigator.pushNamed(
                                    context, AccountQrCodePage.route);
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w),
                            child: CarButton(
                              icon: SvgPicture.asset("assets/images/unlock.svg",
                                  color: Theme.of(context)
                                      .textSelectionTheme
                                      .selectionColor,
                                  width: 24),
                              text: dic['unlock'],
                              onPressed: hasVesting
                                  ? () {
                                      Navigator.pushNamed(
                                        context,
                                        LocksDetailPage.route,
                                        arguments: TransferPageParams(
                                          redirect: LocksDetailPage.route,
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    )),
                Expanded(
                  child: Container(
                    color: Theme.of(context).cardColor,
                    child: Column(
                      children: [
                        Container(
                          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 22.h),
                          margin: EdgeInsets.only(bottom: 10.h, top: 0),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x33000000),
                                blurRadius: 2.0,
                                spreadRadius: 0.0,
                                offset: Offset(
                                  0.0,
                                  3.0,
                                ),
                              )
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              BorderedTitle(title: dic['history']),
                              Row(
                                children: [
                                  Container(
                                    width: 36.w,
                                    height: 28.h,
                                    margin: EdgeInsets.only(right: 8.w),
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      image: DecorationImage(
                                          image: AssetImage(
                                              "assets/images/bg_tag.png"),
                                          fit: BoxFit.fill),
                                    ),
                                    child: Center(
                                      child: Text(
                                          dic[_tab == 0
                                              ? 'all'
                                              : _tab == 1
                                                  ? "in"
                                                  : "out"],
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .toggleableActiveColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              fontFamily: "TitilliumWeb")),
                                    ),
                                  ),
                                  GestureDetector(
                                      onTap: () {
                                        showCupertinoModalPopup(
                                            context: context,
                                            builder: (context) {
                                              return ShowCustomAlterWidget(
                                                  (value) {
                                                setState(() {
                                                  if (value == dic['all']) {
                                                    _tab = 0;
                                                  } else if (value ==
                                                      dic['in']) {
                                                    _tab = 1;
                                                  } else {
                                                    _tab = 2;
                                                  }
                                                });
                                              },
                                                  dic['history'],
                                                  I18n.of(context).getDic(
                                                      i18n_full_dic_ui,
                                                      'common')['cancel'],
                                                  [
                                                    dic['all'],
                                                    dic['in'],
                                                    dic['out']
                                                  ]);
                                            });
                                      },
                                      child: v3.IconButton(
                                        icon: SvgPicture.asset(
                                          'assets/images/icon_screening.svg',
                                          color: Color(0xFF979797),
                                          width: 22.h,
                                        ),
                                      ))
                                ],
                              )
                            ],
                          ),
                        ),
                        Expanded(
                          child: RefreshIndicator(
                            key: _refreshKey,
                            onRefresh: _refreshData,
                            child: ListView(
                              physics: BouncingScrollPhysics(),
                              controller: _scrollController,
                              children: [..._buildTxList()],
                            ),
                          ),
                        )
                      ],
                    ),
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }
}

class CarButton extends StatelessWidget {
  CarButton(
      {@required this.onPressed,
      @required this.text,
      @required this.icon,
      Key key})
      : super(key: key);
  Function() onPressed;
  String text;
  Widget icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTap: () {
          if (onPressed != null) {
            onPressed();
          }
        },
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: BoxDecoration(
            color: Colors.transparent,
            image: DecorationImage(
                image: AssetImage("assets/images/btn_bg.png"),
                fit: BoxFit.fill),
          ),
          alignment: Alignment.center,
          child: Container(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(padding: EdgeInsets.only(bottom: 5.h), child: icon),
                Text(
                  text,
                  style: TextStyle(
                      color:
                          Theme.of(context).textSelectionTheme.selectionColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: "TitilliumWeb"),
                ),
              ],
            ),
          ),
        ));
  }
}

class BalanceCard extends StatelessWidget {
  BalanceCard(this.balancesInfo,
      {this.marketPrices,
      this.symbol,
      this.decimals,
      this.backgroundImage,
      this.unlocks,
      this.onUnlock,
      this.icon});

  final String symbol;
  final int decimals;
  final BalanceData balancesInfo;
  final Map marketPrices;
  final ImageProvider backgroundImage;
  final List unlocks;
  final Function onUnlock;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final dic = I18n.of(context).getDic(i18n_full_dic_app, 'assets');

    final balance = Fmt.balanceTotal(balancesInfo);

    String tokenPrice;
    if (marketPrices[symbol] != null && balancesInfo != null) {
      tokenPrice = Fmt.priceFloor(
          marketPrices[symbol] * Fmt.bigIntToDouble(balance, decimals));
    }

    final primaryColor = Theme.of(context).primaryColor;
    final titleColor = Theme.of(context).cardColor;
    return Container(
      margin: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.w),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(const Radius.circular(16)),
        gradient: LinearGradient(
          colors: [primaryColor, Theme.of(context).accentColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.1, 0.9],
        ),
        image: backgroundImage != null
            ? DecorationImage(
                image: backgroundImage,
                fit: BoxFit.cover,
              )
            : null,
        boxShadow: [
          BoxShadow(
            // color: primaryColor.withAlpha(100),
            color: Color(0x4D000000),
            blurRadius: 5.0,
            spreadRadius: 1.0,
            offset: Offset(5.0, 5.0),
          )
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          Padding(
              padding: EdgeInsets.only(bottom: 22.h),
              child: Row(
                children: [
                  Container(
                      height: 45.w,
                      width: 45.w,
                      margin: EdgeInsets.only(right: 8.w),
                      child: icon),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        Fmt.token(balance, decimals, length: 8),
                        style: TextStyle(
                            color: titleColor,
                            fontSize: 20,
                            letterSpacing: -0.8,
                            fontWeight: FontWeight.w600,
                            fontFamily: "TitilliumWeb"),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Visibility(
                        visible: tokenPrice != null,
                        child: Text(
                          '≈ \$ ${tokenPrice ?? '--.--'}',
                          style: TextStyle(
                              color: titleColor,
                              fontSize: 12,
                              letterSpacing: -0.8,
                              fontWeight: FontWeight.w600,
                              fontFamily: "SF_Pro"),
                        ),
                      ),
                    ],
                  ),
                ],
              )),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    priceItemBuild(
                        SvgPicture.asset(
                          'assets/images/transferrable_icon.svg',
                          color: titleColor,
                        ),
                        dic['available'],
                        Fmt.priceFloorBigInt(
                          Fmt.balanceInt(
                              (balancesInfo?.availableBalance ?? 0).toString()),
                          decimals,
                          lengthMax: 4,
                        ),
                        titleColor),
                    priceItemBuild(
                        SvgPicture.asset(
                          'assets/images/locked_icon.svg',
                          color: titleColor,
                        ),
                        dic['locked'],
                        Fmt.priceFloorBigInt(
                          Fmt.balanceInt(
                              (balancesInfo?.lockedBalance ?? 0).toString()),
                          decimals,
                          lengthMax: 4,
                        ),
                        titleColor),
                    priceItemBuild(
                        SvgPicture.asset(
                          'assets/images/reversed_icon.svg',
                          color: titleColor,
                        ),
                        dic['reserved'],
                        Fmt.priceFloorBigInt(
                          Fmt.balanceInt(
                              (balancesInfo?.reservedBalance ?? 0).toString()),
                          decimals,
                          lengthMax: 4,
                        ),
                        titleColor),
                  ],
                ),
                flex: 1,
              ),
              Expanded(
                child: Container(),
                flex: 1,
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget priceItemBuild(Widget icon, String title, String price, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
                height: 16.w,
                width: 16.w,
                margin: EdgeInsets.only(right: 8.w),
                child: icon),
            Text(
              title,
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: "TitilliumWeb"),
            )
          ],
        ),
        Text(
          price,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              fontFamily: "TitilliumWeb"),
        )
      ],
    );
  }
}

class TransferListItem extends StatelessWidget {
  TransferListItem({
    this.data,
    this.token,
    this.isOut,
    this.hasDetail,
    this.crossChain,
  });

  final TransferData data;
  final String token;
  final String crossChain;
  final bool isOut;
  final bool hasDetail;

  final colorIn = Color(0xFF62CFE4);
  final colorOut = Color(0xFF3394FF);

  @override
  Widget build(BuildContext context) {
    final address = isOut ? data.to : data.from;
    final title =
        Fmt.address(address) ?? data.extrinsicIndex ?? Fmt.address(data.hash);
    final colorFailed = Theme.of(context).unselectedWidgetColor;
    final amount = Fmt.priceFloor(double.parse(data.amount), lengthFixed: 4);
    return ListTile(
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          data.success
              ? isOut
                  ? TransferIcon(type: TransferIconType.rollOut)
                  : TransferIcon(type: TransferIconType.rollIn)
              : TransferIcon(type: TransferIconType.failure)
        ],
      ),
      title: Text(
        '$title${crossChain != null ? ' ($crossChain)' : ''}',
        style: TextStyle(
          color: Theme.of(context).textSelectionTheme.selectionColor,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          fontFamily: 'SF_Pro',
        ),
      ),
      subtitle: Text(
        Fmt.dateTime(
            DateTime.fromMillisecondsSinceEpoch(data.blockTimestamp * 1000)),
        style: TextStyle(
          color: Theme.of(context).textSelectionTheme.selectionColor,
          fontSize: 12,
          fontWeight: FontWeight.w300,
          fontFamily: 'SF_Pro',
        ),
      ),
      trailing: Container(
        width: 110,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${isOut ? '-' : '+'} $amount',
                style: TextStyle(
                    color: data.success
                        ? isOut
                            ? colorOut
                            : colorIn
                        : colorFailed,
                    fontSize: 14,
                    fontFamily: 'TitilliumWeb',
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
      onTap: hasDetail
          ? () {
              Navigator.pushNamed(
                context,
                TransferDetailPage.route,
                arguments: data,
              );
            }
          : null,
    );
  }
}
