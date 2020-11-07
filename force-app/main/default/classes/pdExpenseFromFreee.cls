public with sharing class pdExpenseFromFreee {
    /**
    * 取引(支出)を取得する
     */
    @future(callout=true) 
    public static void getExpenseInfo(Integer months) {
        // 会社情報を取得する
        Integer companyId = getCompany();

        // 勘定科目情報を取得する
        List<AccountInfo> lstAccountInfo = getAccountInfo(companyId);

        // 半年分の経費明細を取得する
        Date startDate;
        List<Expense__c> lstExpense = new List<Expense__c>();
        for(Integer i=0 ; i<months ; i++){
            startDate = Date.today().toStartOfMonth().addMonths(i * (-1));
            Date endDate = startDate.addMonths(1).addDays(-1);

            lstExpense.addAll(getExpense(companyId, lstAccountInfo, startDate, endDate));
        }

        // 経費明細データを削除する
        deleteExpense();

        // 経費情報を登録する
        insert lstExpense;
    }

     /**
     * 経費明細情報を削除する
     * 現在日時の3ヶ月分を削除する
    */
    private static void deleteExpense() {
        Date today = Date.today();
        Date startDate = Date.newInstance(today.year(), today.month() - 3, 1);

        List<Expense__c> lstExpense = [SELECT Id FROM Expense__c WHERE IssueDate__c >= :startDate];
        if (lstExpense.size() != 0) {
            delete lstExpense;
        }
    }

    /**
    * 会社情報を取得する
     */
    private static Integer getCompany() {    
        // 会社情報を取得する
        Http http = new Http();
        String path = 'callout:Freee/companies';
        HttpRequest req = new HttpRequest();
        req.setEndpoint(path);
        req.setMethod('GET');

        HttpResponse res = http.send(req);
        // 会社情報が返ってきたらIIDと名称を設定する
        if (res.getStatusCode() == 200) {
            Map<String, Object> mapCompany = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> lstCompany = (List<Object>)mapCompany.get('companies');
            if (lstCompany.size() == 0) {
                throw new OtherException('会社情報が取得できません');
            }
            else {
                return (Integer)((Map<String, Object>)lstCompany[0]).get('id');
            }
        }
        // エラーで返ってきたら例外をスローする
        else {
            throw new OtherException(getApiErrorMessage(res.getBody()));
        }
    }

    /**
    * 勘定科目情報を取得する
     */
    private static List<AccountInfo> getAccountInfo(Integer companyId) {
        // 勘定科目情報を取得する
        Http http = new Http();
        String path = 'callout:Freee/account_items';
        String parameters = 'company_id=' + companyId;

        HttpRequest req = new HttpRequest();
        req.setEndpoint(path + '?' + parameters);
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        // 正常に返って来たらオブジェクトに設定する
        List<AccountInfo> lstAccoutList = new List<AccountInfo>();
        if (res.getStatusCode() == 200) {
            Map<String, Object> mapBody = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> lstBody = (List<Object>)mapBody.get('account_items');
            for(Object item : lstBody) {
                Map<String, Object> mapItem = (Map<String, Object>)item;
                AccountInfo ai = new AccountInfo();
                ai.Id = (Integer)mapItem.get('id');
                ai.Name = (String)mapItem.get('name');
                lstAccoutList.add(ai);
            }
        }
        else {
            throw new OtherException(getApiErrorMessage(res.getBody()));
        }

        return lstAccoutList;
    }

    /**
    * 経費明細を取得する
    */
    private static List<Expense__c> getExpense(Integer companyId, List<AccountInfo> lstAccountInfo, Date startDate, Date endDate) {
        // 期間を指定して経費明細を取得する
        Http http = new Http();
        String path = 'callout:Freee/deals';
        String parameters = 'company_id=' + companyId;
        parameters += '&type=expense';
        parameters += '&start_issue_date=' + startDate.format().replace('/', '-');
        parameters += '&end_issue_date=' + endDate.format().replace('/', '-');
        parameters += '&limit=100';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(path + '?' + parameters);
        req.setMethod('GET');

        HttpResponse res = http.send(req);

        // 正常に返って来たら経費データを作成する
        List<Expense__c> lstExpense = new List<Expense__c>();
        if(res.getStatusCode() == 200) {
            System.debug(res.getBody());
            Map<String, Object> mapBody = (Map<String, Object>)JSON.deserializeUntyped(res.getBody());
            List<Object> lstDeals = (List<Object>)mapBody.get('deals');
            for(Object deal : lstDeals) {
                Map<String, Object> mapDeal = (Map<String, Object>)deal;
                List<Object> lstDetail = (List<Object>)mapDeal.get('details');
                for(Object detail : lstDetail) {
                    Map<String, Object> mapDetail = (Map<String, Object>)detail;

                    // 経費明細データを作成する
                    Expense__c expense = new Expense__c();
                    // ID
                    expense.Name += String.valueOf((Integer)mapDetail.get('id'));
                    // 計上日
                    expense.AccountDate__c = Date.valueOf((String)mapDeal.get('issue_date'));
                    // 発生日
                    expense.IssueDate__c = Date.valueOf((String)mapDeal.get('issue_date'));
                    // 勘定科目
                    expense.AccountItem__c = getAccountName(lstAccountInfo, (Integer)mapDetail.get('account_item_id'));
                    // 金額
                    expense.Amount__c = (Integer)mapDetail.get('amount');
                    // 備考
                    String description = (String)mapDetail.get('description');
                    if (description == null) {
                        description = '';
                    }
                    expense.Description__c = description.replace(',', '、').replace('¥"', '”');

                    lstExpense.add(expense);
                }
            }
        }
        else {
            throw new OtherException(getApiErrorMessage(res.getBody()));
        }
        
        return lstExpense;
    }

    /**
    * 勘定科目リストから指定IDの勘定科目名を返す
     */
    private static String getAccountName(List<AccountInfo> lstAccountInfo, Integer Id) {
        String ret = null;
        for(AccountInfo ai : lstAccountInfo) {
            if(ai.Id == Id) {
                ret = ai.Name;
                break;
            }
        }

        return ret;
    }

    /**
    * エラーメッセージを設定する
     */
    private static String getApiErrorMessage(String body) {
        System.debug(body);
        String errorMessage = 'Freee APIでエラーが発生しました\r\n';
        if (body != null && body.length() != 0) {
            Map<String, Object> mapError = (Map<String, Object>)JSON.deserializeUntyped(body);
            List<Object> lstError = (List<Object>)(mapError.get('errors'));
            for(Object mapErrorContent : lstError) {
                List<Object> lstMessage = (List<Object>)((Map<String, Object>)mapErrorContent).get('messages');
                for(Object message : lstMessage) {
                    errorMessage += message.toString() + '\r\n';
                }
            }
        }

        return errorMessage;
    }

    public virtual class BaseException extends Exception {}
    public class OtherException extends BaseException {}

    private class AccountInfo {
        Integer Id;
        String Name;
    }
}
